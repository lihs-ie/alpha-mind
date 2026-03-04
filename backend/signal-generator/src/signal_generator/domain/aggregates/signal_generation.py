"""SignalGeneration aggregate root."""

import datetime

from signal_generator.domain.enums.generation_status import GenerationStatus
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.value_objects.failure_detail import FailureDetail
from signal_generator.domain.value_objects.feature_snapshot import FeatureSnapshot
from signal_generator.domain.value_objects.model_diagnostics_snapshot import ModelDiagnosticsSnapshot
from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot
from signal_generator.domain.value_objects.signal_artifact import SignalArtifact


class SignalGeneration:
    """シグナル生成処理の集約ルート。

    状態遷移: pending -> generated / failed
    INV-SG-001: generated のとき signal_artifact と model_diagnostics_snapshot が必須。
    INV-SG-002: failed のとき failure_detail が必須。
    INV-SG-005: identifier は生成後不変。
    """

    def __init__(
        self,
        identifier: str,
        feature_snapshot: FeatureSnapshot,
        universe_count: int,
        trace: str,
    ) -> None:
        self._identifier = identifier
        self._feature_snapshot = feature_snapshot
        self._universe_count = universe_count
        self._trace = trace
        self._status: GenerationStatus = GenerationStatus.PENDING
        self._model_snapshot: ModelSnapshot | None = None
        self._signal_artifact: SignalArtifact | None = None
        self._model_diagnostics_snapshot: ModelDiagnosticsSnapshot | None = None
        self._failure_detail: FailureDetail | None = None
        self._processed_at: datetime.datetime | None = None

    @property
    def identifier(self) -> str:
        return self._identifier

    @property
    def status(self) -> GenerationStatus:
        return self._status

    @property
    def feature_snapshot(self) -> FeatureSnapshot:
        return self._feature_snapshot

    @property
    def model_snapshot(self) -> ModelSnapshot | None:
        return self._model_snapshot

    @property
    def signal_artifact(self) -> SignalArtifact | None:
        return self._signal_artifact

    @property
    def model_diagnostics_snapshot(self) -> ModelDiagnosticsSnapshot | None:
        return self._model_diagnostics_snapshot

    @property
    def failure_detail(self) -> FailureDetail | None:
        return self._failure_detail

    @property
    def universe_count(self) -> int:
        return self._universe_count

    @property
    def trace(self) -> str:
        return self._trace

    @property
    def processed_at(self) -> datetime.datetime | None:
        return self._processed_at

    def resolve_model(self, model_snapshot: ModelSnapshot) -> None:
        """RULE-SG-002: approved モデルのみ推論に利用できる。終端状態では拒否する。"""
        if self._status != GenerationStatus.PENDING:
            raise ValueError(f"{ReasonCode.STATE_CONFLICT}: status={self._status.value} でのモデル解決は不正")
        if not model_snapshot.status.is_usable_for_inference():
            raise ValueError(
                f"{ReasonCode.MODEL_NOT_APPROVED}: モデル '{model_snapshot.model_version}' は "
                f"approved ではない (status={model_snapshot.status.value})"
            )
        self._model_snapshot = model_snapshot

    def complete(
        self,
        signal_artifact: SignalArtifact,
        model_diagnostics_snapshot: ModelDiagnosticsSnapshot,
        processed_at: datetime.datetime,
    ) -> None:
        """推論成功を確定する。INV-SG-001: 終端状態への遷移は拒否する。"""
        if self._status != GenerationStatus.PENDING:
            raise ValueError(f"{ReasonCode.STATE_CONFLICT}: status={self._status.value} から generated への遷移は不正")
        if self._model_snapshot is None:
            raise ValueError("モデルが解決されていないため推論を完了できない")
        if signal_artifact.universe_count != self._universe_count:
            raise ValueError(
                f"SignalArtifact の universe_count({signal_artifact.universe_count})が"
                f"集約の universe_count({self._universe_count})と一致しない"
            )

        self._signal_artifact = signal_artifact
        self._model_diagnostics_snapshot = model_diagnostics_snapshot
        self._processed_at = processed_at
        self._status = GenerationStatus.GENERATED

    def fail(self, failure_detail: FailureDetail, processed_at: datetime.datetime) -> None:
        """推論失敗を確定する。INV-SG-002: 終端状態への遷移は拒否する。"""
        if self._status != GenerationStatus.PENDING:
            raise ValueError(f"{ReasonCode.STATE_CONFLICT}: status={self._status.value} から failed への遷移は不正")
        self._failure_detail = failure_detail
        self._processed_at = processed_at
        self._status = GenerationStatus.FAILED
