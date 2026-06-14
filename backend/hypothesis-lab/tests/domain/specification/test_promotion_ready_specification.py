"""Tests for PromotionReadySpecification (Must-SP-01)."""

from __future__ import annotations

import datetime

import pytest

from domain.model.hypothesis import Hypothesis
from domain.specification.promotion_ready_specification import PromotionReadySpecification
from domain.value_object.demo_window import DemoWindow
from domain.value_object.enums import HypothesisStatus, InsiderRisk, InstrumentType

_NOW = datetime.datetime(2026, 3, 1, tzinfo=datetime.UTC)


def _make_demo_window(demo_period_days: int = 30) -> DemoWindow:
    return DemoWindow(
        started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.UTC),
        demo_period_days=demo_period_days,
    )


def _make_hypothesis(
    auto_promotion_eligible: bool | None = True,
    demo_period_days: int = 30,
    requires_compliance_review: bool | None = False,
    demo_window: DemoWindow | None = None,
) -> Hypothesis:
    return Hypothesis(
        identifier="01JNPQRS000000000000000010",
        symbol="1234",
        instrument_type=InstrumentType.ETF,
        status=HypothesisStatus.DEMO,
        title="Test hypothesis",
        source_evidence=["insight-001"],
        skill_version="v1.0.0",
        instruction_profile_version="v1.0.0",
        updated_at=_NOW,
        insider_risk=InsiderRisk.LOW,
        requires_compliance_review=requires_compliance_review,
        mnpi_self_declared=True,
        auto_promotion_eligible=auto_promotion_eligible,
        demo_window=demo_window if demo_window is not None else _make_demo_window(demo_period_days),
    )


class TestPromotionReadySpecification:
    """Must-SP-01: is_satisfied_by checks RULE-HL-002 conditions."""

    def test_all_conditions_met_returns_true(self) -> None:
        spec = PromotionReadySpecification()
        hypothesis = _make_hypothesis(
            auto_promotion_eligible=True,
            demo_period_days=30,
            requires_compliance_review=False,
        )
        assert spec.is_satisfied_by(hypothesis) is True

    def test_auto_promotion_eligible_false_returns_false(self) -> None:
        spec = PromotionReadySpecification()
        hypothesis = _make_hypothesis(auto_promotion_eligible=False)
        assert spec.is_satisfied_by(hypothesis) is False

    def test_auto_promotion_eligible_none_returns_false(self) -> None:
        spec = PromotionReadySpecification()
        hypothesis = _make_hypothesis(auto_promotion_eligible=None)
        assert spec.is_satisfied_by(hypothesis) is False

    def test_demo_period_days_less_than_30_returns_false(self) -> None:
        spec = PromotionReadySpecification()
        hypothesis = _make_hypothesis(
            auto_promotion_eligible=True,
            demo_period_days=29,
            requires_compliance_review=False,
        )
        assert spec.is_satisfied_by(hypothesis) is False

    def test_requires_compliance_review_true_returns_false(self) -> None:
        spec = PromotionReadySpecification()
        hypothesis = _make_hypothesis(
            auto_promotion_eligible=True,
            demo_period_days=30,
            requires_compliance_review=True,
        )
        assert spec.is_satisfied_by(hypothesis) is False

    def test_no_demo_window_returns_false(self) -> None:
        spec = PromotionReadySpecification()
        hypothesis_no_demo = Hypothesis(
            identifier="01JNPQRS000000000000000010",
            symbol="1234",
            instrument_type=InstrumentType.ETF,
            status=HypothesisStatus.DEMO,
            title="Test hypothesis",
            source_evidence=["insight-001"],
            skill_version="v1.0.0",
            instruction_profile_version="v1.0.0",
            updated_at=_NOW,
            auto_promotion_eligible=True,
            requires_compliance_review=False,
            demo_window=None,
        )
        assert spec.is_satisfied_by(hypothesis_no_demo) is False

    @pytest.mark.parametrize(
        ("auto_promotion_eligible", "demo_period_days", "requires_compliance_review", "expected"),
        [
            (True, 30, False, True),
            (True, 31, False, True),
            (True, 29, False, False),
            (False, 30, False, False),
            (True, 30, True, False),
            (None, 30, False, False),
        ],
    )
    def test_parametrized_conditions(
        self,
        auto_promotion_eligible: bool | None,
        demo_period_days: int,
        requires_compliance_review: bool,
        expected: bool,
    ) -> None:
        spec = PromotionReadySpecification()
        hypothesis = _make_hypothesis(
            auto_promotion_eligible=auto_promotion_eligible,
            demo_period_days=demo_period_days,
            requires_compliance_review=requires_compliance_review,
        )
        assert spec.is_satisfied_by(hypothesis) is expected
