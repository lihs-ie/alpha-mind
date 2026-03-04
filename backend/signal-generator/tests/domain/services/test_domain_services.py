"""Tests for domain services: ApprovedModelPolicy, InferenceConsistencyPolicy."""

import datetime

import pytest

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
            approved_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
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

    def test_failure_reason_code_when_not_satisfied(self) -> None:
        policy = ApprovedModelPolicy()
        candidate_model = ModelSnapshot(
            model_version="model-v2.0.0",
            status=ModelStatus.CANDIDATE,
            approved_at=None,
        )
        assert policy.reason_code(candidate_model) == ReasonCode.MODEL_NOT_APPROVED

    def test_no_reason_code_when_satisfied(self) -> None:
        policy = ApprovedModelPolicy()
        approved_model = ModelSnapshot(
            model_version="model-v1.0.0",
            status=ModelStatus.APPROVED,
            approved_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
        )
        assert policy.reason_code(approved_model) is None


class TestInferenceConsistencyPolicy:
    def test_consistent_counts_satisfies_policy(self) -> None:
        # RULE-SG-004: 推論件数とユニバース件数の一致が必須
        policy = InferenceConsistencyPolicy()
        artifact = SignalArtifact(
            signal_version="signal-v1.0.0",
            storage_path="gs://signal_store/2026-01-01/signals.parquet",
            generated_count=100,
            universe_count=100,
        )
        assert policy.is_satisfied_by(artifact) is True

    def test_block_diagnostics_requires_compliance_review(self) -> None:
        # RULE-SG-007: block フラグ時のコンプライアンスレビュー強制
        policy = InferenceConsistencyPolicy()
        diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.BLOCK,
            requires_compliance_review=True,
        )
        corrected = policy.apply_compliance_review_rule(diagnostics)
        assert corrected.requires_compliance_review is True

    def test_normal_diagnostics_does_not_require_compliance_review(self) -> None:
        policy = InferenceConsistencyPolicy()
        diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        )
        corrected = policy.apply_compliance_review_rule(diagnostics)
        assert corrected.requires_compliance_review is False

    def test_warn_diagnostics_preserves_compliance_review_setting(self) -> None:
        policy = InferenceConsistencyPolicy()
        diagnostics_without_review = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.WARN,
            requires_compliance_review=False,
        )
        corrected = policy.apply_compliance_review_rule(diagnostics_without_review)
        assert corrected.requires_compliance_review is False
