"""Tests for domain services: ApprovedModelPolicy, InferenceConsistencyPolicy."""

import datetime

from signal_generator.domain.enums.degradation_flag import DegradationFlag
from signal_generator.domain.enums.model_status import ModelStatus
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.services.approved_model_policy import ApprovedModelPolicy
from signal_generator.domain.services.inference_consistency_policy import InferenceConsistencyPolicy
from signal_generator.domain.value_objects.model_diagnostics_snapshot import ModelDiagnosticsSnapshot
from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot
from signal_generator.domain.value_objects.signal_artifact import SignalArtifact


class TestApprovedModelPolicy:
    def test_approved_model_satisfies_policy(self) -> None:
        policy = ApprovedModelPolicy()
        approved_model = ModelSnapshot(
            model_version="model-v1.0.0",
            status=ModelStatus.APPROVED,
            approved_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        )
        assert policy.is_satisfied_by(approved_model) is True

    def test_candidate_model_does_not_satisfy_policy(self) -> None:
        # RULE-SG-002: candidate モデルは推論不可
        policy = ApprovedModelPolicy()
        candidate_model = ModelSnapshot(
            model_version="model-v2.0.0",
            status=ModelStatus.CANDIDATE,
            approved_at=None,
        )
        assert policy.is_satisfied_by(candidate_model) is False

    def test_rejected_model_does_not_satisfy_policy(self) -> None:
        # RULE-SG-002: rejected モデルは推論不可
        policy = ApprovedModelPolicy()
        rejected_model = ModelSnapshot(
            model_version="model-v3.0.0",
            status=ModelStatus.REJECTED,
            approved_at=None,
        )
        assert policy.is_satisfied_by(rejected_model) is False

    def test_none_model_does_not_satisfy_policy(self) -> None:
        policy = ApprovedModelPolicy()
        assert policy.is_satisfied_by(None) is False

    def test_reason_code_model_not_approved_when_not_approved(self) -> None:
        policy = ApprovedModelPolicy()
        candidate_model = ModelSnapshot(
            model_version="model-v2.0.0",
            status=ModelStatus.CANDIDATE,
            approved_at=None,
        )
        assert policy.reason_code(candidate_model) == ReasonCode.MODEL_NOT_APPROVED

    def test_reason_code_model_not_found_when_none(self) -> None:
        policy = ApprovedModelPolicy()
        assert policy.reason_code(None) == ReasonCode.MODEL_NOT_FOUND

    def test_no_reason_code_when_satisfied(self) -> None:
        policy = ApprovedModelPolicy()
        approved_model = ModelSnapshot(
            model_version="model-v1.0.0",
            status=ModelStatus.APPROVED,
            approved_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        )
        assert policy.reason_code(approved_model) is None


class TestInferenceConsistencyPolicy:
    def test_consistent_counts_is_satisfied(self) -> None:
        # RULE-SG-004: 推論件数とユニバース件数の一致が必須
        policy = InferenceConsistencyPolicy()
        artifact = SignalArtifact(
            signal_version="signal-v1.0.0",
            storage_path="gs://signal_store/2026-01-01/signals.parquet",
            generated_count=100,
            universe_count=100,
        )
        assert policy.is_count_consistent(artifact) is True

    def test_block_diagnostics_compliance_review_is_satisfied(self) -> None:
        # RULE-SG-007: block フラグ時のコンプライアンスレビュー検証
        policy = InferenceConsistencyPolicy()
        diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.BLOCK,
            requires_compliance_review=True,
        )
        assert policy.is_compliance_review_satisfied(diagnostics) is True

    def test_normal_diagnostics_compliance_review_is_satisfied(self) -> None:
        policy = InferenceConsistencyPolicy()
        diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        )
        assert policy.is_compliance_review_satisfied(diagnostics) is True

    def test_warn_diagnostics_compliance_review_is_satisfied(self) -> None:
        policy = InferenceConsistencyPolicy()
        diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.WARN,
            requires_compliance_review=False,
        )
        assert policy.is_compliance_review_satisfied(diagnostics) is True
