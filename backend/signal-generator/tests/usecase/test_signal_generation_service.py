"""Tests for SignalGenerationService application service."""

import datetime
from unittest.mock import MagicMock

import pandas

from signal_generator.domain.aggregates.signal_dispatch import SignalDispatch
from signal_generator.domain.aggregates.signal_generation import SignalGeneration
from signal_generator.domain.enums.dispatch_status import DispatchStatus
from signal_generator.domain.enums.generation_status import GenerationStatus
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
from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot
from signal_generator.usecase.generate_signal_command import GenerateSignalCommand
from signal_generator.usecase.signal_generation_service import SignalGenerationService

# --- Test fixtures ---

_FIXED_NOW = datetime.datetime(2026, 3, 5, 12, 0, 0, tzinfo=datetime.UTC)
_FIXED_TODAY = datetime.date(2026, 3, 5)
_IDENTIFIER = "01JNABCDEF1234567890123456"
_TRACE = "trace-001"
_FEATURE_VERSION = "v1.0.0"
_STORAGE_PATH = "gs://feature_store/2026-03-05/features.parquet"
_MODEL_VERSION = "model-v1.0.0"
_TARGET_DATE = datetime.date(2026, 3, 5)


def _make_command() -> GenerateSignalCommand:
    return GenerateSignalCommand(
        identifier=_IDENTIFIER,
        target_date=_TARGET_DATE,
        feature_version=_FEATURE_VERSION,
        storage_path=_STORAGE_PATH,
        universe_count=100,
        trace=_TRACE,
    )


def _make_approved_model_snapshot() -> ModelSnapshot:
    return ModelSnapshot(
        model_version=_MODEL_VERSION,
        status=ModelStatus.APPROVED,
        approved_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
    )


def _make_feature_dataframe(row_count: int = 100) -> pandas.DataFrame:
    return pandas.DataFrame({"feature_a": range(row_count), "feature_b": range(row_count)})


def _make_prediction_dataframe(row_count: int = 100) -> pandas.DataFrame:
    return pandas.DataFrame(
        {"ticker": [f"TICK-{i}" for i in range(row_count)], "score": [0.5] * row_count}
    )


class _MockModelPredictor:
    """predict メソッドを持つモック推論モデル。"""

    def __init__(self, prediction_count: int = 100) -> None:
        self._prediction_count = prediction_count

    def predict(self, features: pandas.DataFrame) -> pandas.DataFrame:
        return _make_prediction_dataframe(self._prediction_count)


def _build_service(
    idempotency_key_repository: IdempotencyKeyRepository | None = None,
    model_registry_repository: ModelRegistryRepository | None = None,
    signal_generation_repository: SignalGenerationRepository | None = None,
    signal_dispatch_repository: SignalDispatchRepository | None = None,
    feature_reader: FeatureReader | None = None,
    model_loader: ModelLoader | None = None,
    signal_writer: SignalWriter | None = None,
    signal_event_publisher: SignalEventPublisher | None = None,
    clock: datetime.datetime | None = None,
) -> SignalGenerationService:
    """テスト用にモック依存を注入した SignalGenerationService を構築する。"""
    return SignalGenerationService(
        idempotency_key_repository=idempotency_key_repository or MagicMock(spec=IdempotencyKeyRepository),
        model_registry_repository=model_registry_repository or MagicMock(spec=ModelRegistryRepository),
        signal_generation_repository=signal_generation_repository or MagicMock(spec=SignalGenerationRepository),
        signal_dispatch_repository=signal_dispatch_repository or MagicMock(spec=SignalDispatchRepository),
        feature_reader=feature_reader or MagicMock(spec=FeatureReader),
        model_loader=model_loader or MagicMock(spec=ModelLoader),
        signal_writer=signal_writer or MagicMock(spec=SignalWriter),
        signal_event_publisher=signal_event_publisher or MagicMock(spec=SignalEventPublisher),
        signal_generation_factory=SignalGenerationFactory(),
        signal_dispatch_factory=SignalDispatchFactory(),
        feature_payload_integrity_specification=FeaturePayloadIntegritySpecification(
            clock=lambda: _FIXED_TODAY
        ),
        approved_model_policy=ApprovedModelPolicy(),
        inference_consistency_policy=InferenceConsistencyPolicy(),
        clock=lambda: _FIXED_NOW,
    )


# --- Idempotency Tests ---


class TestIdempotencyCheck:
    """RULE-SG-003: 冪等性チェックのテスト。"""

    def test_duplicate_event_returns_success_without_side_effects(self) -> None:
        """原子的 persist が False を返した場合、副作用なしで重複成功を返す。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = False

        signal_generation_repository = MagicMock(spec=SignalGenerationRepository)

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            signal_generation_repository=signal_generation_repository,
        )

        result = service.execute(_make_command())

        assert result.is_success is True
        assert result.is_duplicate is True
        idempotency_repository.persist.assert_called_once_with(
            f"signal-generator:{_IDENTIFIER}",
            _FIXED_NOW,
            _TRACE,
        )
        signal_generation_repository.persist.assert_not_called()

    def test_new_event_proceeds_to_processing(self) -> None:
        """persist が True を返した場合、通常処理に進む。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.return_value = _make_feature_dataframe()

        model_loader = MagicMock(spec=ModelLoader)
        model_loader.load.return_value = _MockModelPredictor()

        signal_writer = MagicMock(spec=SignalWriter)
        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generated.return_value = "msg-001"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            model_loader=model_loader,
            signal_writer=signal_writer,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is True
        assert result.is_duplicate is False


# --- Input Validation Tests ---


class TestInputValidation:
    """RULE-SG-001: 入力検証のテスト。"""

    def test_invalid_feature_version_causes_failure(self) -> None:
        """feature_version が空文字の場合、REQUEST_VALIDATION_FAILED で失敗する。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        service = _build_service(idempotency_key_repository=idempotency_repository)

        command = GenerateSignalCommand(
            identifier=_IDENTIFIER,
            target_date=_TARGET_DATE,
            feature_version="",
            storage_path=_STORAGE_PATH,
            universe_count=100,
            trace=_TRACE,
        )

        result = service.execute(command)

        assert result.is_success is False
        assert result.reason_code == ReasonCode.REQUEST_VALIDATION_FAILED

    def test_invalid_storage_path_causes_failure(self) -> None:
        """storage_path が gs:// で始まらない場合、REQUEST_VALIDATION_FAILED で失敗する。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        service = _build_service(idempotency_key_repository=idempotency_repository)

        command = GenerateSignalCommand(
            identifier=_IDENTIFIER,
            target_date=_TARGET_DATE,
            feature_version=_FEATURE_VERSION,
            storage_path="/local/path/features.parquet",
            universe_count=100,
            trace=_TRACE,
        )

        result = service.execute(command)

        assert result.is_success is False
        assert result.reason_code == ReasonCode.REQUEST_VALIDATION_FAILED

    def test_future_target_date_causes_failure(self) -> None:
        """target_date が未来日の場合、REQUEST_VALIDATION_FAILED で失敗する。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        service = _build_service(idempotency_key_repository=idempotency_repository)

        command = GenerateSignalCommand(
            identifier=_IDENTIFIER,
            target_date=datetime.date(2099, 12, 31),
            feature_version=_FEATURE_VERSION,
            storage_path=_STORAGE_PATH,
            universe_count=100,
            trace=_TRACE,
        )

        result = service.execute(command)

        assert result.is_success is False
        assert result.reason_code == ReasonCode.REQUEST_VALIDATION_FAILED


# --- Model Resolution Tests ---


class TestModelResolution:
    """RULE-SG-002: approved モデル解決のテスト。"""

    def test_no_approved_model_causes_failure(self) -> None:
        """approved モデルが存在しない場合、MODEL_NOT_FOUND で失敗する。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = None

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generation_failed.return_value = "msg-fail-001"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        assert result.reason_code == ReasonCode.MODEL_NOT_FOUND

    def test_candidate_model_causes_failure(self) -> None:
        """candidate モデルしかない場合、MODEL_NOT_APPROVED で失敗する。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        candidate_model = ModelSnapshot(
            model_version="model-v0.1.0",
            status=ModelStatus.CANDIDATE,
            approved_at=None,
        )
        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = candidate_model

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generation_failed.return_value = "msg-fail-002"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        assert result.reason_code == ReasonCode.MODEL_NOT_APPROVED


# --- Happy Path Tests ---


class TestHappyPath:
    """正常系: features.generated から signal.generated までの全フロー。"""

    def test_successful_signal_generation_flow(self) -> None:
        """正常系のフル処理フローをテストする。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        signal_generation_repository = MagicMock(spec=SignalGenerationRepository)
        signal_dispatch_repository = MagicMock(spec=SignalDispatchRepository)

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.return_value = _make_feature_dataframe()

        model_loader = MagicMock(spec=ModelLoader)
        model_loader.load.return_value = _MockModelPredictor()

        signal_writer = MagicMock(spec=SignalWriter)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generated.return_value = "msg-001"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            signal_generation_repository=signal_generation_repository,
            signal_dispatch_repository=signal_dispatch_repository,
            feature_reader=feature_reader,
            model_loader=model_loader,
            signal_writer=signal_writer,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is True
        assert result.is_duplicate is False
        assert result.reason_code is None

        # FeatureReader が storage_path で呼ばれたか
        feature_reader.read.assert_called_once_with(_STORAGE_PATH)

        # ModelLoader が approved モデルで呼ばれたか
        model_loader.load.assert_called_once_with(
            model_name=_MODEL_VERSION,
            version=_MODEL_VERSION,
        )

        # SignalWriter が呼ばれたか
        signal_writer.write.assert_called_once()

        # SignalGeneration が永続化されたか
        signal_generation_repository.persist.assert_called_once()
        persisted_generation = signal_generation_repository.persist.call_args[0][0]
        assert isinstance(persisted_generation, SignalGeneration)
        assert persisted_generation.status == GenerationStatus.GENERATED

        # SignalDispatch が永続化されたか
        signal_dispatch_repository.persist.assert_called_once()
        persisted_dispatch = signal_dispatch_repository.persist.call_args[0][0]
        assert isinstance(persisted_dispatch, SignalDispatch)
        assert persisted_dispatch.dispatch_status == DispatchStatus.PUBLISHED

        # signal.generated イベントが発行されたか
        event_publisher.publish_signal_generated.assert_called_once()
        published_event = event_publisher.publish_signal_generated.call_args[0][0]
        assert isinstance(published_event, SignalGenerationCompletedEvent)
        assert published_event.model_diagnostics is not None

    def test_signal_writer_called_before_event_publish(self) -> None:
        """RULE-SG-005: signal_store への保存後にのみイベント発行が行われることを検証する。"""
        call_order: list[str] = []

        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.return_value = _make_feature_dataframe()

        model_loader = MagicMock(spec=ModelLoader)
        model_loader.load.return_value = _MockModelPredictor()

        signal_writer = MagicMock(spec=SignalWriter)
        signal_writer.write.side_effect = lambda *positional_arguments, **keyword_arguments: call_order.append("signal_write")

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generated.side_effect = lambda *positional_arguments, **keyword_arguments: (
            call_order.append("event_publish"),
            "msg-001",
        )[-1]

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            model_loader=model_loader,
            signal_writer=signal_writer,
            signal_event_publisher=event_publisher,
        )

        service.execute(_make_command())

        assert call_order == ["signal_write", "event_publish"]


# --- Failure Path Tests ---


class TestFailurePath:
    """異常系: 推論失敗時のフロー。"""

    def test_feature_reader_failure_publishes_failed_event(self) -> None:
        """特徴量読み込み失敗時、signal.generation.failed イベントが発行される。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.side_effect = ConnectionError("Cloud Storage unavailable")

        signal_generation_repository = MagicMock(spec=SignalGenerationRepository)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generation_failed.return_value = "msg-fail-003"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            signal_generation_repository=signal_generation_repository,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        assert result.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE

        # signal.generation.failed が発行されたか
        event_publisher.publish_signal_generation_failed.assert_called_once()
        failed_event = event_publisher.publish_signal_generation_failed.call_args[0][0]
        assert isinstance(failed_event, SignalGenerationFailedEvent)
        assert failed_event.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE

        # SignalGeneration が failed 状態で永続化されたか
        signal_generation_repository.persist.assert_called()
        persisted = signal_generation_repository.persist.call_args[0][0]
        assert persisted.status == GenerationStatus.FAILED

    def test_model_loader_failure_publishes_failed_event(self) -> None:
        """モデルロード失敗時、signal.generation.failed イベントが発行される。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.return_value = _make_feature_dataframe()

        model_loader = MagicMock(spec=ModelLoader)
        model_loader.load.side_effect = ConnectionError("MLflow unavailable")

        signal_generation_repository = MagicMock(spec=SignalGenerationRepository)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generation_failed.return_value = "msg-fail-004"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            model_loader=model_loader,
            signal_generation_repository=signal_generation_repository,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        assert result.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE

    def test_prediction_count_mismatch_causes_failure(self) -> None:
        """推論件数がユニバース件数と一致しない場合、SIGNAL_GENERATION_FAILED で失敗する。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.return_value = _make_feature_dataframe(100)

        # 推論が 50 件しか返さない (ユニバース 100 件と不一致)
        model_loader = MagicMock(spec=ModelLoader)
        model_loader.load.return_value = _MockModelPredictor(prediction_count=50)

        signal_generation_repository = MagicMock(spec=SignalGenerationRepository)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generation_failed.return_value = "msg-fail-005"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            model_loader=model_loader,
            signal_generation_repository=signal_generation_repository,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        assert result.reason_code == ReasonCode.SIGNAL_GENERATION_FAILED

    def test_event_publish_failure_after_complete_does_not_crash(self) -> None:
        """complete() 後にイベント発行が失敗しても、異常終了せず失敗結果を返す。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.return_value = _make_feature_dataframe()

        model_loader = MagicMock(spec=ModelLoader)
        model_loader.load.return_value = _MockModelPredictor()

        signal_writer = MagicMock(spec=SignalWriter)
        signal_generation_repository = MagicMock(spec=SignalGenerationRepository)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generated.side_effect = RuntimeError("Pub/Sub unavailable")

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            model_loader=model_loader,
            signal_writer=signal_writer,
            signal_generation_repository=signal_generation_repository,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        assert result.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE
        # SignalGeneration は generated 状態で永続化されている
        signal_generation_repository.persist.assert_called_once()
        persisted = signal_generation_repository.persist.call_args[0][0]
        assert persisted.status == GenerationStatus.GENERATED

    def test_timeout_error_maps_to_dependency_timeout(self) -> None:
        """TimeoutError は DEPENDENCY_TIMEOUT にマッピングされる。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.side_effect = TimeoutError("read timeout")

        signal_generation_repository = MagicMock(spec=SignalGenerationRepository)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generation_failed.return_value = "msg-fail-timeout"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            signal_generation_repository=signal_generation_repository,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        assert result.reason_code == ReasonCode.DEPENDENCY_TIMEOUT

    def test_error_detail_is_sanitized(self) -> None:
        """例外の生メッセージが外部結果に露出しないことを検証する。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.side_effect = RuntimeError("gs://secret-bucket/internal/path.parquet connection failed")

        signal_generation_repository = MagicMock(spec=SignalGenerationRepository)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generation_failed.return_value = "msg-fail-sanitize"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            signal_generation_repository=signal_generation_repository,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        # 結果の detail に生の例外メッセージが含まれていないことを検証
        assert "secret-bucket" not in (result.detail or "")
        assert "connection failed" not in (result.detail or "")

    def test_failed_event_publish_failure_does_not_crash_on_model_resolution(self) -> None:
        """モデル解決失敗時に失敗イベント発行が例外を投げても異常終了しない。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = None

        signal_generation_repository = MagicMock(spec=SignalGenerationRepository)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generation_failed.side_effect = RuntimeError("Pub/Sub down")

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            signal_generation_repository=signal_generation_repository,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        assert result.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE
        # SignalGeneration は failed 状態で永続化されている
        signal_generation_repository.persist.assert_called_once()

    def test_failed_event_publish_failure_does_not_crash_on_inference(self) -> None:
        """推論失敗時に失敗イベント発行が例外を投げても異常終了しない。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.side_effect = RuntimeError("Cloud Storage unavailable")

        signal_generation_repository = MagicMock(spec=SignalGenerationRepository)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generation_failed.side_effect = RuntimeError("Pub/Sub down")

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            signal_generation_repository=signal_generation_repository,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        assert result.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE

    def test_model_loader_value_error_not_mapped_to_count_mismatch(self) -> None:
        """model_loader の ValueError が件数不一致に誤マッピングされないことを検証する。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.return_value = _make_feature_dataframe()

        model_loader = MagicMock(spec=ModelLoader)
        model_loader.load.side_effect = ValueError("model signature mismatch")

        signal_generation_repository = MagicMock(spec=SignalGenerationRepository)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generation_failed.return_value = "msg-fail"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            model_loader=model_loader,
            signal_generation_repository=signal_generation_repository,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        # ValueError は REQUEST_VALIDATION_FAILED にマッピングされる (件数不一致ではない)
        assert result.reason_code == ReasonCode.REQUEST_VALIDATION_FAILED
        assert result.detail != "推論件数がユニバース件数と一致しない"

    def test_connection_error_maps_to_dependency_unavailable(self) -> None:
        """ConnectionError は DEPENDENCY_UNAVAILABLE にマッピングされる。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.side_effect = ConnectionError("connection refused")

        signal_generation_repository = MagicMock(spec=SignalGenerationRepository)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generation_failed.return_value = "msg-fail"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            signal_generation_repository=signal_generation_repository,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        assert result.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE

    def test_unknown_exception_maps_to_internal_error(self) -> None:
        """未分類の例外は INTERNAL_ERROR にマッピングされる。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.side_effect = KeyError("unexpected key")

        signal_generation_repository = MagicMock(spec=SignalGenerationRepository)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generation_failed.return_value = "msg-fail"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            signal_generation_repository=signal_generation_repository,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        assert result.reason_code == ReasonCode.INTERNAL_ERROR


# --- Model Version Verification Tests ---


class TestModelVersionVerification:
    """モデルバージョン検証のテスト。"""

    def test_approved_model_version_is_used_for_inference(self) -> None:
        """approved モデルの model_version が ModelLoader に渡されることを検証する。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        approved_model = ModelSnapshot(
            model_version="model-v2.5.0",
            status=ModelStatus.APPROVED,
            approved_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.UTC),
        )
        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = approved_model

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.return_value = _make_feature_dataframe()

        model_loader = MagicMock(spec=ModelLoader)
        model_loader.load.return_value = _MockModelPredictor()

        signal_writer = MagicMock(spec=SignalWriter)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generated.return_value = "msg-001"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            model_loader=model_loader,
            signal_writer=signal_writer,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is True
        model_loader.load.assert_called_once_with(
            model_name="model-v2.5.0",
            version="model-v2.5.0",
        )

    def test_model_version_included_in_completed_event(self) -> None:
        """完了イベントに approved モデルの model_version が含まれることを検証する。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        approved_model = ModelSnapshot(
            model_version="model-v3.0.0",
            status=ModelStatus.APPROVED,
            approved_at=datetime.datetime(2026, 2, 15, tzinfo=datetime.UTC),
        )
        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = approved_model

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.return_value = _make_feature_dataframe()

        model_loader = MagicMock(spec=ModelLoader)
        model_loader.load.return_value = _MockModelPredictor()

        signal_writer = MagicMock(spec=SignalWriter)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generated.return_value = "msg-001"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            model_loader=model_loader,
            signal_writer=signal_writer,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is True
        published_event = event_publisher.publish_signal_generated.call_args[0][0]
        assert published_event.model_version == "model-v3.0.0"


# --- Idempotency Key Recording Tests ---


class TestIdempotencyKeyRecording:
    """冪等性キーの記録テスト (原子的 acquire 方式)。"""

    def test_idempotency_key_acquired_atomically_on_success(self) -> None:
        """正常完了時、冪等性キーは処理開始時に原子的に acquire される。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = _make_approved_model_snapshot()

        feature_reader = MagicMock(spec=FeatureReader)
        feature_reader.read.return_value = _make_feature_dataframe()

        model_loader = MagicMock(spec=ModelLoader)
        model_loader.load.return_value = _MockModelPredictor()

        signal_writer = MagicMock(spec=SignalWriter)

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generated.return_value = "msg-001"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            feature_reader=feature_reader,
            model_loader=model_loader,
            signal_writer=signal_writer,
            signal_event_publisher=event_publisher,
        )

        service.execute(_make_command())

        # persist は処理開始時に1回だけ呼ばれる (原子的 acquire)
        idempotency_repository.persist.assert_called_once_with(
            f"signal-generator:{_IDENTIFIER}",
            _FIXED_NOW,
            _TRACE,
        )

    def test_idempotency_key_acquired_on_failure(self) -> None:
        """処理失敗時も、冪等性キーは処理開始時に acquire されている。"""
        idempotency_repository = MagicMock(spec=IdempotencyKeyRepository)
        idempotency_repository.persist.return_value = True

        model_registry = MagicMock(spec=ModelRegistryRepository)
        model_registry.find_by_status.return_value = None

        event_publisher = MagicMock(spec=SignalEventPublisher)
        event_publisher.publish_signal_generation_failed.return_value = "msg-fail-001"

        service = _build_service(
            idempotency_key_repository=idempotency_repository,
            model_registry_repository=model_registry,
            signal_event_publisher=event_publisher,
        )

        result = service.execute(_make_command())

        assert result.is_success is False
        # persist は処理開始時に1回だけ呼ばれる
        idempotency_repository.persist.assert_called_once_with(
            f"signal-generator:{_IDENTIFIER}",
            _FIXED_NOW,
            _TRACE,
        )
