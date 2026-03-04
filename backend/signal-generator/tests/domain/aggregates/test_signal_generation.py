"""Tests for SignalGeneration aggregate root."""

import datetime

import pytest

from signal_generator.domain.aggregates.signal_generation import SignalGeneration
from signal_generator.domain.enums.degradation_flag import DegradationFlag
from signal_generator.domain.enums.generation_status import GenerationStatus
from signal_generator.domain.enums.model_status import ModelStatus
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.value_objects.failure_detail import FailureDetail
from signal_generator.domain.value_objects.feature_snapshot import FeatureSnapshot
from signal_generator.domain.value_objects.model_diagnostics_snapshot import ModelDiagnosticsSnapshot
from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot
from signal_generator.domain.value_objects.signal_artifact import SignalArtifact


def _make_feature_snapshot() -> FeatureSnapshot:
    return FeatureSnapshot(
        target_date=datetime.date(2026, 1, 1),
        feature_version="v1.0.0",
        storage_path="gs://feature_store/2026-01-01/features.parquet",
    )


def _make_model_snapshot() -> ModelSnapshot:
    return ModelSnapshot(
        model_version="model-v1.0.0",
        status=ModelStatus.APPROVED,
        approved_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
    )


def _make_signal_artifact() -> SignalArtifact:
    return SignalArtifact(
        signal_version="signal-v1.0.0",
        storage_path="gs://signal_store/2026-01-01/signals.parquet",
        generated_count=100,
        universe_count=100,
    )


def _make_model_diagnostics(
    degradation_flag: DegradationFlag = DegradationFlag.NORMAL,
    requires_compliance_review: bool = False,
) -> ModelDiagnosticsSnapshot:
    return ModelDiagnosticsSnapshot(
        degradation_flag=degradation_flag,
        requires_compliance_review=requires_compliance_review,
    )


class TestSignalGenerationCreation:
    def test_create_pending_generation(self) -> None:
        generation = SignalGeneration(
            identifier="01JNABCDEF1234567890123456",
            feature_snapshot=_make_feature_snapshot(),
            universe_count=100,
            trace="trace-001",
        )
        assert generation.identifier == "01JNABCDEF1234567890123456"
        assert generation.status == GenerationStatus.PENDING
        assert generation.universe_count == 100
        assert generation.trace == "trace-001"
        assert generation.model_snapshot is None
        assert generation.signal_artifact is None
        assert generation.failure_detail is None
        assert generation.model_diagnostics_snapshot is None
        assert generation.processed_at is None

    def test_identifier_is_immutable_after_creation(self) -> None:
        # RULE-SG-009 / INV-SG-005: identifier は生成後不変
        generation = SignalGeneration(
            identifier="01JNABCDEF1234567890123456",
            feature_snapshot=_make_feature_snapshot(),
            universe_count=100,
            trace="trace-001",
        )
        with pytest.raises(Exception):
            generation.identifier = "new-identifier"  # type: ignore[misc]


class TestSignalGenerationResolveModel:
    def test_resolve_approved_model(self) -> None:
        generation = SignalGeneration(
            identifier="01JNABCDEF1234567890123456",
            feature_snapshot=_make_feature_snapshot(),
            universe_count=100,
            trace="trace-001",
        )
        model = _make_model_snapshot()
        generation.resolve_model(model)
        assert generation.model_snapshot == model

    def test_resolve_non_approved_model_fails(self) -> None:
        # RULE-SG-002: approved 以外のモデルは推論に利用できない
        generation = SignalGeneration(
            identifier="01JNABCDEF1234567890123456",
            feature_snapshot=_make_feature_snapshot(),
            universe_count=100,
            trace="trace-001",
        )
        candidate_model = ModelSnapshot(
            model_version="model-v2.0.0",
            status=ModelStatus.CANDIDATE,
            approved_at=None,
        )
        with pytest.raises(ValueError, match="MODEL_NOT_APPROVED"):
            generation.resolve_model(candidate_model)


class TestSignalGenerationComplete:
    def test_complete_from_pending_to_generated(self) -> None:
        # RULE-SG-005: signal_store 保存後に成功確定できる
        generation = SignalGeneration(
            identifier="01JNABCDEF1234567890123456",
            feature_snapshot=_make_feature_snapshot(),
            universe_count=100,
            trace="trace-001",
        )
        generation.resolve_model(_make_model_snapshot())
        diagnostics = _make_model_diagnostics()
        artifact = _make_signal_artifact()
        processed_at = datetime.datetime(2026, 1, 1, 10, 0, 0, tzinfo=datetime.timezone.utc)

        generation.complete(
            signal_artifact=artifact,
            model_diagnostics_snapshot=diagnostics,
            processed_at=processed_at,
        )

        assert generation.status == GenerationStatus.GENERATED
        assert generation.signal_artifact == artifact
        assert generation.model_diagnostics_snapshot == diagnostics
        assert generation.processed_at == processed_at

    def test_complete_requires_model_resolved(self) -> None:
        generation = SignalGeneration(
            identifier="01JNABCDEF1234567890123456",
            feature_snapshot=_make_feature_snapshot(),
            universe_count=100,
            trace="trace-001",
        )
        # モデル未解決で complete しようとするとエラー
        with pytest.raises(ValueError):
            generation.complete(
                signal_artifact=_make_signal_artifact(),
                model_diagnostics_snapshot=_make_model_diagnostics(),
                processed_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            )

    def test_complete_on_failed_status_raises_state_conflict(self) -> None:
        # INV-SG-001/failed 状態からの complete は拒否する
        generation = SignalGeneration(
            identifier="01JNABCDEF1234567890123456",
            feature_snapshot=_make_feature_snapshot(),
            universe_count=100,
            trace="trace-001",
        )
        generation.fail(
            failure_detail=FailureDetail(reason_code=ReasonCode.MODEL_NOT_APPROVED, retryable=False),
            processed_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
        )
        with pytest.raises(ValueError, match="STATE_CONFLICT"):
            generation.complete(
                signal_artifact=_make_signal_artifact(),
                model_diagnostics_snapshot=_make_model_diagnostics(),
                processed_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            )

    def test_block_degradation_flag_sets_compliance_review_required(self) -> None:
        # RULE-SG-007: degradationFlag=block のとき requiresComplianceReview=true
        generation = SignalGeneration(
            identifier="01JNABCDEF1234567890123456",
            feature_snapshot=_make_feature_snapshot(),
            universe_count=100,
            trace="trace-001",
        )
        generation.resolve_model(_make_model_snapshot())
        block_diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.BLOCK,
            requires_compliance_review=True,
        )
        generation.complete(
            signal_artifact=_make_signal_artifact(),
            model_diagnostics_snapshot=block_diagnostics,
            processed_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
        )
        assert generation.model_diagnostics_snapshot is not None
        assert generation.model_diagnostics_snapshot.requires_compliance_review is True


class TestSignalGenerationFail:
    def test_fail_from_pending(self) -> None:
        # RULE-SG-008: 失敗時は reasonCode を保存する
        generation = SignalGeneration(
            identifier="01JNABCDEF1234567890123456",
            feature_snapshot=_make_feature_snapshot(),
            universe_count=100,
            trace="trace-001",
        )
        failure = FailureDetail(reason_code=ReasonCode.MODEL_NOT_APPROVED, retryable=False)
        processed_at = datetime.datetime(2026, 1, 1, 10, 0, 0, tzinfo=datetime.timezone.utc)

        generation.fail(failure_detail=failure, processed_at=processed_at)

        assert generation.status == GenerationStatus.FAILED
        assert generation.failure_detail == failure
        assert generation.processed_at == processed_at

    def test_fail_on_generated_status_raises_state_conflict(self) -> None:
        generation = SignalGeneration(
            identifier="01JNABCDEF1234567890123456",
            feature_snapshot=_make_feature_snapshot(),
            universe_count=100,
            trace="trace-001",
        )
        generation.resolve_model(_make_model_snapshot())
        generation.complete(
            signal_artifact=_make_signal_artifact(),
            model_diagnostics_snapshot=_make_model_diagnostics(),
            processed_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
        )
        with pytest.raises(ValueError, match="STATE_CONFLICT"):
            generation.fail(
                failure_detail=FailureDetail(reason_code=ReasonCode.STATE_CONFLICT, retryable=False),
                processed_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            )
