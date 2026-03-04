"""Tests for domain value objects."""

import datetime

import pytest

from signal_generator.domain.enums.degradation_flag import DegradationFlag
from signal_generator.domain.enums.dispatch_status import DispatchStatus
from signal_generator.domain.enums.event_type import EventType
from signal_generator.domain.enums.model_status import ModelStatus
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.value_objects.dispatch_decision import DispatchDecision
from signal_generator.domain.value_objects.failure_detail import FailureDetail
from signal_generator.domain.value_objects.feature_snapshot import FeatureSnapshot
from signal_generator.domain.value_objects.model_diagnostics_snapshot import ModelDiagnosticsSnapshot
from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot
from signal_generator.domain.value_objects.signal_artifact import SignalArtifact


class TestFeatureSnapshot:
    def test_create_with_required_fields(self) -> None:
        snapshot = FeatureSnapshot(
            target_date=datetime.date(2026, 1, 1),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-01-01/features.parquet",
        )
        assert snapshot.target_date == datetime.date(2026, 1, 1)
        assert snapshot.feature_version == "v1.0.0"
        assert snapshot.storage_path == "gs://feature_store/2026-01-01/features.parquet"

    def test_equality_by_value(self) -> None:
        snapshot_a = FeatureSnapshot(
            target_date=datetime.date(2026, 1, 1),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-01-01/features.parquet",
        )
        snapshot_b = FeatureSnapshot(
            target_date=datetime.date(2026, 1, 1),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-01-01/features.parquet",
        )
        assert snapshot_a == snapshot_b

    def test_immutability(self) -> None:
        snapshot = FeatureSnapshot(
            target_date=datetime.date(2026, 1, 1),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-01-01/features.parquet",
        )
        with pytest.raises(Exception):
            snapshot.feature_version = "v2.0.0"  # type: ignore[misc]


class TestModelSnapshot:
    def test_create_approved_model(self) -> None:
        approved_at = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
        snapshot = ModelSnapshot(
            model_version="model-v1.0.0",
            status=ModelStatus.APPROVED,
            approved_at=approved_at,
        )
        assert snapshot.model_version == "model-v1.0.0"
        assert snapshot.status == ModelStatus.APPROVED
        assert snapshot.approved_at == approved_at

    def test_create_candidate_model_without_approved_at(self) -> None:
        snapshot = ModelSnapshot(
            model_version="model-v2.0.0",
            status=ModelStatus.CANDIDATE,
            approved_at=None,
        )
        assert snapshot.approved_at is None

    def test_equality_by_value(self) -> None:
        approved_at = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
        snapshot_a = ModelSnapshot(
            model_version="model-v1.0.0",
            status=ModelStatus.APPROVED,
            approved_at=approved_at,
        )
        snapshot_b = ModelSnapshot(
            model_version="model-v1.0.0",
            status=ModelStatus.APPROVED,
            approved_at=approved_at,
        )
        assert snapshot_a == snapshot_b

    def test_immutability(self) -> None:
        snapshot = ModelSnapshot(
            model_version="model-v1.0.0",
            status=ModelStatus.APPROVED,
            approved_at=None,
        )
        with pytest.raises(Exception):
            snapshot.model_version = "model-v2.0.0"  # type: ignore[misc]


class TestModelDiagnosticsSnapshot:
    def test_create_with_required_fields(self) -> None:
        snapshot = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        )
        assert snapshot.degradation_flag == DegradationFlag.NORMAL
        assert snapshot.requires_compliance_review is False

    def test_create_with_optional_fields(self) -> None:
        snapshot = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.WARN,
            requires_compliance_review=False,
            cost_adjusted_return=0.12,
            slippage_adjusted_sharpe=1.5,
        )
        assert snapshot.cost_adjusted_return == 0.12
        assert snapshot.slippage_adjusted_sharpe == 1.5

    def test_block_flag_must_have_compliance_review_true(self) -> None:
        # RULE-SG-007: degradationFlag=block のとき requiresComplianceReview=true
        with pytest.raises(ValueError):
            ModelDiagnosticsSnapshot(
                degradation_flag=DegradationFlag.BLOCK,
                requires_compliance_review=False,
            )

    def test_block_flag_with_compliance_review_true_is_valid(self) -> None:
        snapshot = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.BLOCK,
            requires_compliance_review=True,
        )
        assert snapshot.requires_compliance_review is True

    def test_equality_by_value(self) -> None:
        snapshot_a = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        )
        snapshot_b = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        )
        assert snapshot_a == snapshot_b

    def test_immutability(self) -> None:
        snapshot = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        )
        with pytest.raises(Exception):
            snapshot.degradation_flag = DegradationFlag.BLOCK  # type: ignore[misc]


class TestSignalArtifact:
    def test_create_with_matching_counts(self) -> None:
        artifact = SignalArtifact(
            signal_version="signal-v1.0.0",
            storage_path="gs://signal_store/2026-01-01/signals.parquet",
            generated_count=100,
            universe_count=100,
        )
        assert artifact.signal_version == "signal-v1.0.0"
        assert artifact.generated_count == 100
        assert artifact.universe_count == 100

    def test_counts_mismatch_raises_error(self) -> None:
        # RULE-SG-004: 推論件数とユニバース件数は一致必須
        with pytest.raises(ValueError):
            SignalArtifact(
                signal_version="signal-v1.0.0",
                storage_path="gs://signal_store/2026-01-01/signals.parquet",
                generated_count=99,
                universe_count=100,
            )

    def test_equality_by_value(self) -> None:
        artifact_a = SignalArtifact(
            signal_version="signal-v1.0.0",
            storage_path="gs://signal_store/2026-01-01/signals.parquet",
            generated_count=100,
            universe_count=100,
        )
        artifact_b = SignalArtifact(
            signal_version="signal-v1.0.0",
            storage_path="gs://signal_store/2026-01-01/signals.parquet",
            generated_count=100,
            universe_count=100,
        )
        assert artifact_a == artifact_b

    def test_immutability(self) -> None:
        artifact = SignalArtifact(
            signal_version="signal-v1.0.0",
            storage_path="gs://signal_store/2026-01-01/signals.parquet",
            generated_count=100,
            universe_count=100,
        )
        with pytest.raises(Exception):
            artifact.signal_version = "signal-v2.0.0"  # type: ignore[misc]


class TestFailureDetail:
    def test_create_with_required_fields(self) -> None:
        detail = FailureDetail(
            reason_code=ReasonCode.MODEL_NOT_APPROVED,
            retryable=False,
        )
        assert detail.reason_code == ReasonCode.MODEL_NOT_APPROVED
        assert detail.retryable is False
        assert detail.detail is None

    def test_create_with_optional_detail(self) -> None:
        detail = FailureDetail(
            reason_code=ReasonCode.DEPENDENCY_TIMEOUT,
            retryable=True,
            detail="Connection timed out after 30s",
        )
        assert detail.detail == "Connection timed out after 30s"

    def test_equality_by_value(self) -> None:
        detail_a = FailureDetail(
            reason_code=ReasonCode.MODEL_NOT_APPROVED,
            retryable=False,
        )
        detail_b = FailureDetail(
            reason_code=ReasonCode.MODEL_NOT_APPROVED,
            retryable=False,
        )
        assert detail_a == detail_b

    def test_immutability(self) -> None:
        detail = FailureDetail(
            reason_code=ReasonCode.MODEL_NOT_APPROVED,
            retryable=False,
        )
        with pytest.raises(Exception):
            detail.reason_code = ReasonCode.STATE_CONFLICT  # type: ignore[misc]


class TestDispatchDecision:
    def test_create_pending_dispatch(self) -> None:
        decision = DispatchDecision(dispatch_status=DispatchStatus.PENDING)
        assert decision.dispatch_status == DispatchStatus.PENDING
        assert decision.published_event is None
        assert decision.reason_code is None

    def test_create_published_dispatch(self) -> None:
        decision = DispatchDecision(
            dispatch_status=DispatchStatus.PUBLISHED,
            published_event=EventType.SIGNAL_GENERATED,
        )
        assert decision.dispatch_status == DispatchStatus.PUBLISHED
        assert decision.published_event == EventType.SIGNAL_GENERATED

    def test_create_failed_dispatch(self) -> None:
        decision = DispatchDecision(
            dispatch_status=DispatchStatus.FAILED,
            reason_code=ReasonCode.DEPENDENCY_TIMEOUT,
        )
        assert decision.dispatch_status == DispatchStatus.FAILED
        assert decision.reason_code == ReasonCode.DEPENDENCY_TIMEOUT

    def test_equality_by_value(self) -> None:
        decision_a = DispatchDecision(dispatch_status=DispatchStatus.PENDING)
        decision_b = DispatchDecision(dispatch_status=DispatchStatus.PENDING)
        assert decision_a == decision_b

    def test_immutability(self) -> None:
        decision = DispatchDecision(dispatch_status=DispatchStatus.PENDING)
        with pytest.raises(Exception):
            decision.dispatch_status = DispatchStatus.PUBLISHED  # type: ignore[misc]
