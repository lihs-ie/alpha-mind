"""SignalGenerationService application service."""

import datetime
import logging
from collections.abc import Callable

from signal_generator.domain.aggregates.signal_generation import SignalGeneration
from signal_generator.domain.enums.degradation_flag import DegradationFlag
from signal_generator.domain.enums.dispatch_status import DispatchStatus
from signal_generator.domain.enums.event_type import EventType
from signal_generator.domain.enums.model_status import ModelStatus
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.events.signal_generation_completed_event import (
    SignalGenerationCompletedEvent,
)
from signal_generator.domain.events.signal_generation_failed_event import (
    SignalGenerationFailedEvent,
)
from signal_generator.domain.factories.signal_dispatch_factory import SignalDispatchFactory
from signal_generator.domain.factories.signal_generation_factory import SignalGenerationFactory
from signal_generator.domain.ports.event_publisher import SignalEventPublisher
from signal_generator.domain.ports.feature_reader import FeatureReader
from signal_generator.domain.ports.model_loader import ModelLoader
from signal_generator.domain.ports.signal_writer import SignalWriter
from signal_generator.domain.repositories.idempotency_key_repository import (
    IdempotencyKeyRepository,
)
from signal_generator.domain.repositories.model_registry_repository import (
    ModelRegistryRepository,
)
from signal_generator.domain.repositories.signal_dispatch_repository import (
    SignalDispatchRepository,
)
from signal_generator.domain.repositories.signal_generation_repository import (
    SignalGenerationRepository,
)
from signal_generator.domain.services.approved_model_policy import ApprovedModelPolicy
from signal_generator.domain.services.inference_consistency_policy import (
    InferenceConsistencyPolicy,
)
from signal_generator.domain.specifications.feature_payload_integrity_specification import (
    FeaturePayloadIntegritySpecification,
)
from signal_generator.domain.value_objects.failure_detail import FailureDetail
from signal_generator.domain.value_objects.feature_snapshot import FeatureSnapshot
from signal_generator.domain.value_objects.model_diagnostics_snapshot import (
    ModelDiagnosticsSnapshot,
)
from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot
from signal_generator.domain.value_objects.signal_artifact import SignalArtifact
from signal_generator.usecase.generate_signal_command import GenerateSignalCommand
from signal_generator.usecase.generate_signal_result import GenerateSignalResult

logger = logging.getLogger(__name__)

_SERVICE_PREFIX = "signal-generator"


class SignalGenerationService:
    """受信イベントから推論/保存/発行までをオーケストレーションするアプリケーションサービス。

    業務ルール本体はドメイン層に委譲し、本サービスは処理フローの組み立てのみを担う。
    """

    def __init__(
        self,
        idempotency_key_repository: IdempotencyKeyRepository,
        model_registry_repository: ModelRegistryRepository,
        signal_generation_repository: SignalGenerationRepository,
        signal_dispatch_repository: SignalDispatchRepository,
        feature_reader: FeatureReader,
        model_loader: ModelLoader,
        signal_writer: SignalWriter,
        signal_event_publisher: SignalEventPublisher,
        signal_generation_factory: SignalGenerationFactory,
        signal_dispatch_factory: SignalDispatchFactory,
        feature_payload_integrity_specification: FeaturePayloadIntegritySpecification,
        approved_model_policy: ApprovedModelPolicy,
        inference_consistency_policy: InferenceConsistencyPolicy,
        clock: Callable[[], datetime.datetime],
    ) -> None:
        self._idempotency_key_repository = idempotency_key_repository
        self._model_registry_repository = model_registry_repository
        self._signal_generation_repository = signal_generation_repository
        self._signal_dispatch_repository = signal_dispatch_repository
        self._feature_reader = feature_reader
        self._model_loader = model_loader
        self._signal_writer = signal_writer
        self._signal_event_publisher = signal_event_publisher
        self._signal_generation_factory = signal_generation_factory
        self._signal_dispatch_factory = signal_dispatch_factory
        self._feature_payload_integrity_specification = feature_payload_integrity_specification
        self._approved_model_policy = approved_model_policy
        self._inference_consistency_policy = inference_consistency_policy
        self._clock = clock

    def execute(self, command: GenerateSignalCommand) -> GenerateSignalResult:
        """features.generated イベントを処理し、シグナル生成を実行する。

        処理フロー:
        1. 冪等性キー acquire (RULE-SG-003) - 原子的 persist
        2. 入力検証 (RULE-SG-001)
        3. approved モデル解決 (RULE-SG-002)
        4. 特徴量読み込み
        5. モデルロード
        6. 推論実行
        7. 件数整合検証 (RULE-SG-004)
        8. signal_store へ保存 (RULE-SG-005)
        9. 集約永続化
        10. イベント発行 (RULE-SG-006)

        retryable な失敗時は冪等性キーを terminate して再処理を許可する。
        """
        idempotency_key = f"{_SERVICE_PREFIX}:{command.identifier}"
        now = self._clock()

        # Step 1: 冪等性チェック (RULE-SG-003) - 原子的 acquire で競合を防止
        try:
            acquired = self._idempotency_key_repository.persist(idempotency_key, now, command.trace)
        except Exception:
            logger.exception("冪等性キー acquire 失敗: identifier=%s", command.identifier)
            return GenerateSignalResult.failure(
                reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
                detail="冪等性キー acquire に失敗しました",
            )
        if not acquired:
            logger.info("重複イベント検出: identifier=%s", command.identifier)
            return GenerateSignalResult.duplicate()

        # Step 2: 入力検証 (RULE-SG-001)
        feature_snapshot = FeatureSnapshot(
            target_date=command.target_date,
            feature_version=command.feature_version,
            storage_path=command.storage_path,
        )
        if not self._feature_payload_integrity_specification.is_satisfied_by(feature_snapshot):
            reason_code = ReasonCode.REQUEST_VALIDATION_FAILED
            logger.warning(
                "入力検証失敗: identifier=%s, reason=%s",
                command.identifier,
                reason_code,
            )
            return self._handle_pre_inference_failure(command, now, reason_code)

        # Step 3: approved モデル解決 (RULE-SG-002)
        try:
            model_snapshot = self._model_registry_repository.find_by_status(ModelStatus.APPROVED)
        except TimeoutError:
            logger.exception("モデルレジストリタイムアウト: identifier=%s", command.identifier)
            return self._handle_pre_inference_failure(command, now, ReasonCode.DEPENDENCY_TIMEOUT)
        except Exception:
            logger.exception("モデルレジストリ読み取り失敗: identifier=%s", command.identifier)
            return self._handle_pre_inference_failure(command, now, ReasonCode.DEPENDENCY_UNAVAILABLE)
        if not self._approved_model_policy.is_satisfied_by(model_snapshot):
            model_reason_code = self._approved_model_policy.reason_code(model_snapshot)
            assert model_reason_code is not None
            logger.warning(
                "モデル解決失敗: identifier=%s, reason=%s",
                command.identifier,
                model_reason_code,
            )
            return self._handle_pre_inference_failure(command, now, model_reason_code)

        assert model_snapshot is not None

        # Step 4-11: 推論実行フロー
        return self._execute_inference(
            command=command,
            feature_snapshot=feature_snapshot,
            model_snapshot=model_snapshot,
            now=now,
        )

    def _execute_inference(
        self,
        command: GenerateSignalCommand,
        feature_snapshot: FeatureSnapshot,
        model_snapshot: ModelSnapshot,
        now: datetime.datetime,
    ) -> GenerateSignalResult:
        """推論実行フロー (Step 4-11)。

        complete() 前後で try を分割し、complete() 後は fail() へ戻さない。
        """
        # SignalGeneration 集約を作成
        generation = self._signal_generation_factory.from_features_generated_event(
            identifier=command.identifier,
            feature_snapshot=feature_snapshot,
            universe_count=command.universe_count,
            trace=command.trace,
        )

        # モデル解決を集約に記録
        generation.resolve_model(model_snapshot)

        # Phase 1: complete() 前 - 失敗時は generation.fail() で処理
        try:
            # Step 4: 特徴量読み込み
            feature_dataframe = self._feature_reader.read(command.storage_path)

            # Step 5: モデルロード
            model = self._model_loader.load(
                model_name=model_snapshot.model_version,
                version=model_snapshot.model_version,
            )

            # Step 6: 推論実行
            prediction_dataframe = model.predict(feature_dataframe)
        except TimeoutError:
            logger.exception("依存先タイムアウト: identifier=%s", command.identifier)
            return self._handle_inference_failure(
                generation=generation,
                command=command,
                now=now,
                reason_code=ReasonCode.DEPENDENCY_TIMEOUT,
                detail="依存先タイムアウト",
            )
        except Exception as error:
            logger.exception("推論処理失敗: identifier=%s", command.identifier)
            reason_code = self._classify_exception_reason_code(error)
            return self._handle_inference_failure(
                generation=generation,
                command=command,
                now=now,
                reason_code=reason_code,
                detail="推論処理中にエラーが発生しました",
            )

        # Step 7: 件数整合検証 (RULE-SG-004) - ドメインポリシーに委譲
        prediction_count = len(prediction_dataframe)
        if not self._inference_consistency_policy.is_count_consistent(
            generated_count=prediction_count,
            universe_count=command.universe_count,
        ):
            return self._handle_inference_failure(
                generation=generation,
                command=command,
                now=now,
                reason_code=ReasonCode.SIGNAL_GENERATION_FAILED,
                detail="推論件数がユニバース件数と一致しない",
            )

        # SignalArtifact 構築
        signal_version = self._build_signal_version(command)
        signal_storage_path = self._build_signal_storage_path(command, signal_version)
        signal_artifact = SignalArtifact(
            signal_version=signal_version,
            storage_path=signal_storage_path,
            generated_count=prediction_count,
            universe_count=command.universe_count,
        )

        # ModelDiagnosticsSnapshot 構築 (RULE-SG-006, RULE-SG-007)
        model_diagnostics = self._build_model_diagnostics()

        # Step 8: signal_store へ保存 (RULE-SG-005: 保存後にのみイベント発行)
        try:
            self._signal_writer.write(prediction_dataframe, signal_storage_path)
        except TimeoutError:
            logger.exception("signal_store 書き込みタイムアウト: identifier=%s", command.identifier)
            return self._handle_inference_failure(
                generation=generation,
                command=command,
                now=now,
                reason_code=ReasonCode.DEPENDENCY_TIMEOUT,
                detail="signal_store 書き込みタイムアウト",
            )
        except Exception as error:
            logger.exception("signal_store 書き込み失敗: identifier=%s", command.identifier)
            reason_code = self._classify_exception_reason_code(error)
            return self._handle_inference_failure(
                generation=generation,
                command=command,
                now=now,
                reason_code=reason_code,
                detail="signal_store 書き込みに失敗しました",
            )

        # 集約を完了状態にする (推論完了時点のタイムスタンプを使用)
        completed_at = self._clock()
        generation.complete(signal_artifact, model_diagnostics, completed_at)

        # Step 9: SignalGeneration 集約を永続化
        self._signal_generation_repository.persist(generation)

        # Phase 2: complete() 後 - fail() へ戻さない
        # INV-SG-004: 既に signal.generated が publish 済みの場合はスキップ
        try:
            existing_dispatch = self._signal_dispatch_repository.find(command.identifier)
        except Exception:
            logger.exception("dispatch 検索失敗: identifier=%s", command.identifier)
            existing_dispatch = None
        if (
            existing_dispatch is not None
            and existing_dispatch.dispatch_status == DispatchStatus.PUBLISHED
            and existing_dispatch.published_event == EventType.SIGNAL_GENERATED
        ):
            logger.info("既に publish 済み: identifier=%s", command.identifier)
            return GenerateSignalResult.success()

        try:
            # Step 10: イベント発行
            completed_event = SignalGenerationCompletedEvent(
                identifier=command.identifier,
                signal_version=signal_version,
                model_version=model_snapshot.model_version,
                feature_version=command.feature_version,
                storage_path=signal_storage_path,
                model_diagnostics=model_diagnostics,
                trace=command.trace,
                occurred_at=completed_at,
            )
            self._signal_event_publisher.publish_signal_generated(completed_event)
        except ValueError:
            logger.exception("イベント発行バリデーション失敗: identifier=%s", command.identifier)
            return self._finalize_failure(
                command=command,
                retryable=False,
                reason_code=ReasonCode.INTERNAL_ERROR,
                detail="イベント発行に失敗しました",
            )
        except Exception:
            logger.exception("イベント発行失敗: identifier=%s", command.identifier)
            return self._finalize_failure(
                command=command,
                retryable=True,
                reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
                detail="イベント発行に失敗しました",
            )

        # publish 成功後の dispatch 永続化 — publish 済みなので retryable=False
        try:
            dispatch = self._signal_dispatch_factory.from_signal_generation(
                identifier=command.identifier,
                trace=command.trace,
            )
            dispatch.publish(EventType.SIGNAL_GENERATED, completed_at)
            self._signal_dispatch_repository.persist(dispatch)
        except Exception:
            logger.exception("dispatch 永続化失敗: identifier=%s", command.identifier)
            return self._finalize_failure(
                command=command,
                retryable=False,
                reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
                detail="dispatch 永続化に失敗しました",
            )

        return GenerateSignalResult.success()

    def _handle_pre_inference_failure(
        self,
        command: GenerateSignalCommand,
        now: datetime.datetime,
        reason_code: ReasonCode,
    ) -> GenerateSignalResult:
        """推論前フェーズ(入力検証・モデル解決)の失敗ハンドリング。"""
        retryable = reason_code not in ReasonCode.non_retryable()
        try:
            self._persist_failed_generation(command, now, reason_code)
        except Exception:
            logger.exception("失敗集約永続化失敗: identifier=%s", command.identifier)
        try:
            self._publish_failed_event_and_dispatch(command, now, reason_code)
        except Exception:
            logger.exception("失敗イベント発行失敗: identifier=%s", command.identifier)
            return self._finalize_failure(
                command,
                retryable=True,
                reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
                detail="失敗イベント発行に失敗しました",
            )
        return self._finalize_failure(
            command,
            retryable=retryable,
            reason_code=reason_code,
        )

    def _handle_inference_failure(
        self,
        generation: SignalGeneration,
        command: GenerateSignalCommand,
        now: datetime.datetime,
        reason_code: ReasonCode,
        detail: str,
    ) -> GenerateSignalResult:
        """推論実行中の失敗ハンドリング。

        detail はサニタイズ済みメッセージのみを受け取る。
        生の例外文言は logger で記録し、外部には伝播しない。
        """
        retryable = reason_code not in ReasonCode.non_retryable()
        failure_detail = FailureDetail(
            reason_code=reason_code,
            retryable=retryable,
            detail=detail,
        )
        generation.fail(failure_detail, now)
        self._signal_generation_repository.persist(generation)
        try:
            self._publish_failed_event_and_dispatch(command, now, reason_code, detail)
        except Exception:
            logger.exception("失敗イベント発行失敗: identifier=%s", command.identifier)
            return self._finalize_failure(
                command,
                retryable=True,
                reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
                detail="失敗イベント発行に失敗しました",
            )
        return self._finalize_failure(
            command,
            retryable=retryable,
            reason_code=reason_code,
            detail=detail,
        )

    def _persist_failed_generation(
        self,
        command: GenerateSignalCommand,
        now: datetime.datetime,
        reason_code: ReasonCode,
    ) -> None:
        """失敗状態の SignalGeneration 集約を作成して永続化する。"""
        feature_snapshot = FeatureSnapshot(
            target_date=command.target_date,
            feature_version=command.feature_version,
            storage_path=command.storage_path,
        )
        generation = self._signal_generation_factory.from_features_generated_event(
            identifier=command.identifier,
            feature_snapshot=feature_snapshot,
            universe_count=command.universe_count,
            trace=command.trace,
        )
        failure_detail = FailureDetail(
            reason_code=reason_code,
            retryable=reason_code not in ReasonCode.non_retryable(),
        )
        generation.fail(failure_detail, now)
        self._signal_generation_repository.persist(generation)

    def _publish_failed_event_and_dispatch(
        self,
        command: GenerateSignalCommand,
        now: datetime.datetime,
        reason_code: ReasonCode,
        detail: str | None = None,
    ) -> None:
        """失敗イベントの発行と SignalDispatch 集約の永続化を行う。

        INV-SG-004: 既に publish/failed 済みの dispatch がある場合は発行をスキップする。
        """
        existing_dispatch = self._signal_dispatch_repository.find(command.identifier)
        if existing_dispatch is not None and existing_dispatch.dispatch_status != DispatchStatus.PENDING:
            return

        failed_event = SignalGenerationFailedEvent(
            identifier=command.identifier,
            reason_code=reason_code,
            trace=command.trace,
            occurred_at=now,
            detail=detail,
        )
        self._signal_event_publisher.publish_signal_generation_failed(failed_event)

        dispatch = self._signal_dispatch_factory.from_signal_generation(
            identifier=command.identifier,
            trace=command.trace,
        )
        dispatch.publish(EventType.SIGNAL_GENERATION_FAILED, now)
        self._signal_dispatch_repository.persist(dispatch)

    def _finalize_failure(
        self,
        command: GenerateSignalCommand,
        retryable: bool,
        reason_code: ReasonCode,
        detail: str | None = None,
    ) -> GenerateSignalResult:
        """失敗結果を返す。retryable な場合は冪等性キーを terminate して再処理を許可する。"""
        if retryable:
            idempotency_key = f"{_SERVICE_PREFIX}:{command.identifier}"
            try:
                self._idempotency_key_repository.terminate(idempotency_key)
            except Exception:
                logger.exception("冪等性キー terminate 失敗: identifier=%s", command.identifier)
        return GenerateSignalResult.failure(reason_code=reason_code, detail=detail)

    def _build_signal_version(self, command: GenerateSignalCommand) -> str:
        """signal_version を採番する。"""
        return f"signal-{command.target_date.isoformat()}-{command.feature_version}"

    def _build_signal_storage_path(self, command: GenerateSignalCommand, signal_version: str) -> str:
        """推論結果の保存パスを構築する。"""
        return f"gs://signal-store/{command.target_date.isoformat()}/{signal_version}.parquet"

    def _build_model_diagnostics(self) -> ModelDiagnosticsSnapshot:
        """ModelDiagnosticsSnapshot を構築する (RULE-SG-006, RULE-SG-007)。

        RULE-SG-007: 現時点では NORMAL 固定。将来的にモデル診断結果から動的に構築する。
        degradationFlag=block の場合は requiresComplianceReview=true が必須であり、
        ModelDiagnosticsSnapshot.__post_init__ と InferenceConsistencyPolicy で保護されている。
        """
        return ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        )

    def _classify_exception_reason_code(self, error: Exception) -> ReasonCode:
        """例外の種別からReasonCodeを分類する。"""
        if isinstance(error, (ConnectionError, OSError)):
            return ReasonCode.DEPENDENCY_UNAVAILABLE
        return ReasonCode.INTERNAL_ERROR
