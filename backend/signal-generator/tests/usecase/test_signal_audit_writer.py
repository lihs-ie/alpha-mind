"""Tests for SignalAuditWriter application service."""

import datetime

from signal_generator.domain.aggregates.signal_generation import SignalGeneration
from signal_generator.domain.enums.degradation_flag import DegradationFlag
from signal_generator.domain.enums.generation_status import GenerationStatus
from signal_generator.domain.enums.model_status import ModelStatus
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.value_objects.failure_detail import FailureDetail
from signal_generator.domain.value_objects.feature_snapshot import FeatureSnapshot
from signal_generator.domain.value_objects.model_diagnostics_snapshot import (
    ModelDiagnosticsSnapshot,
)
from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot
from signal_generator.domain.value_objects.signal_artifact import SignalArtifact
from signal_generator.usecase.signal_audit_writer import AuditEntry, SignalAuditWriter

# --- Test fixtures ---

_FIXED_NOW = datetime.datetime(2026, 3, 5, 12, 0, 0, tzinfo=datetime.UTC)
_IDENTIFIER = "01JNABCDEF1234567890123456"
_TRACE = "trace-001"


def _make_completed_generation() -> SignalGeneration:
    """generated 状態の SignalGeneration を作成する。"""
    generation = SignalGeneration(
        identifier=_IDENTIFIER,
        feature_snapshot=FeatureSnapshot(
            target_date=datetime.date(2026, 3, 5),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-03-05/features.parquet",
        ),
        universe_count=100,
        trace=_TRACE,
    )
    generation.resolve_model(
        ModelSnapshot(
            model_version="model-v1.0.0",
            status=ModelStatus.APPROVED,
            approved_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        )
    )
    generation.complete(
        signal_artifact=SignalArtifact(
            signal_version="signal-v1.0.0",
            storage_path="gs://signal_store/2026-03-05/signals.parquet",
            generated_count=100,
            universe_count=100,
        ),
        model_diagnostics_snapshot=ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        ),
        processed_at=_FIXED_NOW,
    )
    return generation


def _make_failed_generation() -> SignalGeneration:
    """failed 状態の SignalGeneration を作成する。"""
    generation = SignalGeneration(
        identifier=_IDENTIFIER,
        feature_snapshot=FeatureSnapshot(
            target_date=datetime.date(2026, 3, 5),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-03-05/features.parquet",
        ),
        universe_count=100,
        trace=_TRACE,
    )
    generation.fail(
        failure_detail=FailureDetail(
            reason_code=ReasonCode.MODEL_NOT_FOUND,
            retryable=False,
        ),
        processed_at=_FIXED_NOW,
    )
    return generation


class TestSignalAuditWriterCreation:
    """SignalAuditWriter のインスタンス化テスト。"""

    def test_can_create_audit_writer(self) -> None:
        writer = SignalAuditWriter()
        assert writer is not None


class TestBuildAuditEntryFromCompletedGeneration:
    """生成成功時の監査エントリ構築テスト。"""

    def test_builds_audit_entry_for_completed_generation(self) -> None:
        """generated 状態の集約から監査エントリを構築できる。"""
        writer = SignalAuditWriter()
        generation = _make_completed_generation()

        entry = writer.build_audit_entry(generation)

        assert isinstance(entry, AuditEntry)
        assert entry.identifier == _IDENTIFIER
        assert entry.trace == _TRACE
        assert entry.status == GenerationStatus.GENERATED
        assert entry.model_version == "model-v1.0.0"
        assert entry.reason_code is None

    def test_completed_entry_includes_signal_version(self) -> None:
        """generated 状態の監査エントリに signal_version が含まれる。"""
        writer = SignalAuditWriter()
        generation = _make_completed_generation()

        entry = writer.build_audit_entry(generation)

        assert entry.signal_version == "signal-v1.0.0"


class TestBuildAuditEntryFromFailedGeneration:
    """生成失敗時の監査エントリ構築テスト。"""

    def test_builds_audit_entry_for_failed_generation(self) -> None:
        """failed 状態の集約から監査エントリを構築できる。"""
        writer = SignalAuditWriter()
        generation = _make_failed_generation()

        entry = writer.build_audit_entry(generation)

        assert isinstance(entry, AuditEntry)
        assert entry.identifier == _IDENTIFIER
        assert entry.trace == _TRACE
        assert entry.status == GenerationStatus.FAILED
        assert entry.reason_code == ReasonCode.MODEL_NOT_FOUND
        assert entry.model_version is None
        assert entry.signal_version is None

    def test_failed_entry_includes_reason_code(self) -> None:
        """failed 状態の監査エントリに reason_code が含まれる。"""
        writer = SignalAuditWriter()
        generation = _make_failed_generation()

        entry = writer.build_audit_entry(generation)

        assert entry.reason_code == ReasonCode.MODEL_NOT_FOUND


class TestAuditWriterDoesNotContainInferenceLogic:
    """SignalAuditWriter が推論判定ロジックを含まないことを検証する。"""

    def test_audit_writer_does_not_have_predict_method(self) -> None:
        """SignalAuditWriter は predict メソッドを持たない。"""
        writer = SignalAuditWriter()
        assert not hasattr(writer, "predict")

    def test_audit_writer_does_not_have_execute_method(self) -> None:
        """SignalAuditWriter は execute メソッドを持たない (推論実行は SignalGenerationService の責務)。"""
        writer = SignalAuditWriter()
        assert not hasattr(writer, "execute")
