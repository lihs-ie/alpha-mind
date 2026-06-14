"""Tests for PromotionReadySpecification."""

import datetime

from hypothesis_lab.domain.aggregates.hypothesis import Hypothesis
from hypothesis_lab.domain.enums.hypothesis_status import HypothesisStatus
from hypothesis_lab.domain.enums.instrument_type import InstrumentType
from hypothesis_lab.domain.specifications.promotion_ready_specification import PromotionReadySpecification
from hypothesis_lab.domain.value_objects.demo_window import DemoWindow


def make_demo_hypothesis(
    demo_period_days: int = 31,
    promotable: bool = True,
    requires_compliance_review: bool = False,
    status: HypothesisStatus = HypothesisStatus.DEMO,
) -> Hypothesis:
    """Helper to create a Hypothesis in DEMO state for specification testing."""
    hypothesis = Hypothesis(
        identifier="01HXXXXXXXXXXXXXXXXXXX",
        symbol="1234",
        instrument_type=InstrumentType.ETF,
        status=status,
        title="Test Hypothesis",
        source_evidence=["evidence-1"],
        skill_version="v1.0.0",
        instruction_profile_version="v1.0.0",
        requires_compliance_review=requires_compliance_review,
        updated_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
    )
    if status == HypothesisStatus.DEMO:
        demo_window = DemoWindow(
            started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.timezone.utc),
            demo_period_days=demo_period_days,
        )
        hypothesis.complete_demo_run(demo_window=demo_window, promotable=promotable)
    return hypothesis


class TestPromotionReadySpecification:
    def test_all_conditions_true_returns_true(self) -> None:
        """All promotion conditions met -> True."""
        hypothesis = make_demo_hypothesis(
            demo_period_days=31,
            promotable=True,
            requires_compliance_review=False,
        )
        spec = PromotionReadySpecification()
        assert spec.is_satisfied_by(hypothesis) is True

    def test_exactly_30_demo_days_returns_true(self) -> None:
        """demo_period_days == 30 -> True (boundary condition)."""
        hypothesis = make_demo_hypothesis(
            demo_period_days=30,
            promotable=True,
            requires_compliance_review=False,
        )
        spec = PromotionReadySpecification()
        assert spec.is_satisfied_by(hypothesis) is True

    def test_demo_period_days_less_than_30_returns_false(self) -> None:
        """AC-03: demo_period_days < 30 -> False."""
        hypothesis = make_demo_hypothesis(
            demo_period_days=29,
            promotable=True,
            requires_compliance_review=False,
        )
        spec = PromotionReadySpecification()
        assert spec.is_satisfied_by(hypothesis) is False

    def test_requires_compliance_review_true_returns_false(self) -> None:
        """AC-12: requires_compliance_review=True -> False."""
        hypothesis = make_demo_hypothesis(
            demo_period_days=31,
            promotable=True,
            requires_compliance_review=True,
        )
        spec = PromotionReadySpecification()
        assert spec.is_satisfied_by(hypothesis) is False

    def test_not_demo_status_returns_false(self) -> None:
        """Hypothesis not in DEMO status -> False."""
        hypothesis = make_demo_hypothesis(
            demo_period_days=31,
            promotable=True,
            requires_compliance_review=False,
            status=HypothesisStatus.BACKTESTED,
        )
        spec = PromotionReadySpecification()
        assert spec.is_satisfied_by(hypothesis) is False

    def test_promotable_false_returns_false(self) -> None:
        """promotable=False -> False."""
        hypothesis = make_demo_hypothesis(
            demo_period_days=31,
            promotable=False,
            requires_compliance_review=False,
        )
        spec = PromotionReadySpecification()
        assert spec.is_satisfied_by(hypothesis) is False

    def test_no_demo_window_returns_false(self) -> None:
        """No demo_window set -> False (promotable not evaluable)."""
        hypothesis = Hypothesis(
            identifier="01HXXXXXXXXXXXXXXXXXXX",
            symbol="1234",
            instrument_type=InstrumentType.ETF,
            status=HypothesisStatus.DEMO,
            title="Test Hypothesis",
            source_evidence=["evidence-1"],
            skill_version="v1.0.0",
            instruction_profile_version="v1.0.0",
            requires_compliance_review=False,
            updated_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
        )
        spec = PromotionReadySpecification()
        assert spec.is_satisfied_by(hypothesis) is False
