"""Tests for PromotionEligibilityPolicy domain service."""

import datetime

import pytest

from hypothesis_lab.domain.aggregates.hypothesis import Hypothesis
from hypothesis_lab.domain.enums.hypothesis_status import HypothesisStatus
from hypothesis_lab.domain.enums.insider_risk import InsiderRisk
from hypothesis_lab.domain.enums.instrument_type import InstrumentType
from hypothesis_lab.domain.enums.promotion_eligibility import PromotionEligibility
from hypothesis_lab.domain.services.promotion_eligibility_policy import PromotionEligibilityPolicy
from hypothesis_lab.domain.value_objects.demo_window import DemoWindow
from hypothesis_lab.domain.value_objects.performance_metrics import PerformanceMetrics


def make_demo_hypothesis_ready_for_promotion(
    instrument_type: InstrumentType = InstrumentType.ETF,
    insider_risk: InsiderRisk = InsiderRisk.LOW,
    mnpi_self_declared: bool | None = True,
    requires_compliance_review: bool = False,
    demo_period_days: int = 31,
    symbol: str = "1234",
) -> Hypothesis:
    """Helper: creates a Hypothesis in DEMO state with promotable=True demo run."""
    hypothesis = Hypothesis(
        identifier="01HXXXXXXXXXXXXXXXXXXX",
        symbol=symbol,
        instrument_type=instrument_type,
        status=HypothesisStatus.DEMO,
        title="Test Hypothesis",
        source_evidence=["evidence-1"],
        skill_version="v1.0.0",
        instruction_profile_version="v1.0.0",
        insider_risk=insider_risk,
        requires_compliance_review=requires_compliance_review,
        mnpi_self_declared=mnpi_self_declared,
        updated_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
    )
    demo_window = DemoWindow(
        started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
        ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.timezone.utc),
        demo_period_days=demo_period_days,
    )
    hypothesis.complete_demo_run(demo_window=demo_window, promotable=True)
    return hypothesis


class TestPromotionEligibilityPolicyAutoPromotion:
    def test_etf_low_risk_all_conditions_met_returns_eligible_for_auto(self) -> None:
        """AC-01: ETF + low insider_risk + mnpi=True + >= 30 days + no compliance review -> eligible_for_auto."""
        hypothesis = make_demo_hypothesis_ready_for_promotion(
            instrument_type=InstrumentType.ETF,
            insider_risk=InsiderRisk.LOW,
            mnpi_self_declared=True,
            requires_compliance_review=False,
            demo_period_days=31,
        )
        policy = PromotionEligibilityPolicy()
        result = policy.check(hypothesis, partner_restricted_symbols=set())
        assert result == PromotionEligibility.ELIGIBLE_FOR_AUTO

    def test_exactly_30_days_qualifies_for_auto(self) -> None:
        """demo_period_days == 30 is sufficient for auto-promotion."""
        hypothesis = make_demo_hypothesis_ready_for_promotion(
            instrument_type=InstrumentType.ETF,
            insider_risk=InsiderRisk.LOW,
            mnpi_self_declared=True,
            requires_compliance_review=False,
            demo_period_days=30,
        )
        policy = PromotionEligibilityPolicy()
        result = policy.check(hypothesis, partner_restricted_symbols=set())
        assert result == PromotionEligibility.ELIGIBLE_FOR_AUTO


class TestPromotionEligibilityPolicyManualPromotion:
    def test_stock_instrument_returns_eligible_for_manual(self) -> None:
        """AC-02: STOCK instrument_type -> eligible_for_manual (not auto)."""
        hypothesis = make_demo_hypothesis_ready_for_promotion(
            instrument_type=InstrumentType.STOCK,
            insider_risk=InsiderRisk.LOW,
            mnpi_self_declared=True,
            requires_compliance_review=False,
            demo_period_days=31,
        )
        policy = PromotionEligibilityPolicy()
        result = policy.check(hypothesis, partner_restricted_symbols=set())
        assert result == PromotionEligibility.ELIGIBLE_FOR_MANUAL


class TestPromotionEligibilityPolicyBlocked:
    def test_demo_period_less_than_30_days_returns_blocked(self) -> None:
        """AC-03: demo_period_days < 30 -> blocked."""
        hypothesis = make_demo_hypothesis_ready_for_promotion(
            demo_period_days=29,
        )
        policy = PromotionEligibilityPolicy()
        result = policy.check(hypothesis, partner_restricted_symbols=set())
        assert result == PromotionEligibility.BLOCKED

    def test_mnpi_self_declared_false_returns_blocked(self) -> None:
        """AC-04: mnpi_self_declared=False -> blocked."""
        hypothesis = make_demo_hypothesis_ready_for_promotion(
            mnpi_self_declared=False,
        )
        policy = PromotionEligibilityPolicy()
        result = policy.check(hypothesis, partner_restricted_symbols=set())
        assert result == PromotionEligibility.BLOCKED

    def test_mnpi_self_declared_none_returns_blocked(self) -> None:
        """mnpi_self_declared=None (unset) -> blocked."""
        hypothesis = make_demo_hypothesis_ready_for_promotion(mnpi_self_declared=None)
        policy = PromotionEligibilityPolicy()
        result = policy.check(hypothesis, partner_restricted_symbols=set())
        assert result == PromotionEligibility.BLOCKED

    def test_requires_compliance_review_true_returns_blocked(self) -> None:
        """AC-12: requires_compliance_review=True -> blocked."""
        hypothesis = make_demo_hypothesis_ready_for_promotion(
            requires_compliance_review=True,
        )
        policy = PromotionEligibilityPolicy()
        result = policy.check(hypothesis, partner_restricted_symbols=set())
        assert result == PromotionEligibility.BLOCKED

    def test_symbol_in_partner_restricted_symbols_returns_blocked(self) -> None:
        """Symbol in partner_restricted_symbols -> blocked."""
        hypothesis = make_demo_hypothesis_ready_for_promotion(symbol="RESTRICTED")
        policy = PromotionEligibilityPolicy()
        result = policy.check(hypothesis, partner_restricted_symbols={"RESTRICTED"})
        assert result == PromotionEligibility.BLOCKED

    def test_medium_insider_risk_returns_blocked(self) -> None:
        """insider_risk=MEDIUM -> blocked."""
        hypothesis = make_demo_hypothesis_ready_for_promotion(
            insider_risk=InsiderRisk.MEDIUM,
        )
        policy = PromotionEligibilityPolicy()
        result = policy.check(hypothesis, partner_restricted_symbols=set())
        assert result == PromotionEligibility.BLOCKED

    def test_high_insider_risk_returns_blocked(self) -> None:
        """insider_risk=HIGH -> blocked."""
        hypothesis = make_demo_hypothesis_ready_for_promotion(
            insider_risk=InsiderRisk.HIGH,
        )
        policy = PromotionEligibilityPolicy()
        result = policy.check(hypothesis, partner_restricted_symbols=set())
        assert result == PromotionEligibility.BLOCKED

    def test_promotable_false_returns_blocked(self) -> None:
        """promotable=False -> blocked."""
        # Construct directly with status=DEMO then call complete_demo_run(promotable=False)
        # which transitions to REJECTED. The policy does not check status, so BLOCKED is correct.
        hypothesis = Hypothesis(
            identifier="01HXXXXXXXXXXXXXXXXXXX",
            symbol="1234",
            instrument_type=InstrumentType.ETF,
            status=HypothesisStatus.DEMO,
            title="Test Hypothesis",
            source_evidence=["evidence-1"],
            skill_version="v1.0.0",
            instruction_profile_version="v1.0.0",
            insider_risk=InsiderRisk.LOW,
            requires_compliance_review=False,
            mnpi_self_declared=True,
            updated_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
        )
        demo_window = DemoWindow(
            started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.timezone.utc),
            demo_period_days=31,
        )
        hypothesis.complete_demo_run(demo_window=demo_window, promotable=False)
        policy = PromotionEligibilityPolicy()
        result = policy.check(hypothesis, partner_restricted_symbols=set())
        assert result == PromotionEligibility.BLOCKED
