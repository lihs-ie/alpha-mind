"""Tests for PromotionEligibilityPolicy domain service (Must-DS-01)."""

from __future__ import annotations

import datetime

from domain.model.hypothesis import Hypothesis
from domain.service.promotion_eligibility_policy import PromotionEligibilityPolicy
from domain.value_object.demo_window import DemoWindow
from domain.value_object.enums import HypothesisStatus, InsiderRisk, InstrumentType

_NOW = datetime.datetime(2026, 3, 1, tzinfo=datetime.UTC)


def _make_eligible_etf_hypothesis(
    symbol: str = "1234",
    insider_risk: InsiderRisk = InsiderRisk.LOW,
    requires_compliance_review: bool = False,
    mnpi_self_declared: bool = True,
    demo_period_days: int = 30,
) -> Hypothesis:
    demo_window = DemoWindow(
        started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.UTC),
        demo_period_days=demo_period_days,
    )
    return Hypothesis(
        identifier="01JNPQRS000000000000000010",
        symbol=symbol,
        instrument_type=InstrumentType.ETF,
        status=HypothesisStatus.DEMO,
        title="Test ETF hypothesis",
        source_evidence=["insight-001"],
        skill_version="v1.0.0",
        instruction_profile_version="v1.0.0",
        updated_at=_NOW,
        insider_risk=insider_risk,
        requires_compliance_review=requires_compliance_review,
        mnpi_self_declared=mnpi_self_declared,
        auto_promotion_eligible=True,
        demo_window=demo_window,
    )


class TestPromotionEligibilityPolicyInstantiation:
    """Must-DS-01: no IO, instantiable without external dependencies."""

    def test_instantiation_requires_no_io(self) -> None:
        policy = PromotionEligibilityPolicy()
        assert policy is not None


class TestCheckAutoEligibility:
    """Must-DS-01, Must-S-02: all 7 auto-promotion conditions."""

    def test_all_conditions_met_returns_true(self) -> None:
        policy = PromotionEligibilityPolicy()
        hypothesis = _make_eligible_etf_hypothesis()
        assert policy.check_auto_eligibility(hypothesis, partner_restricted_symbols=[]) is True

    def test_demo_period_days_less_than_30_returns_false(self) -> None:
        policy = PromotionEligibilityPolicy()
        hypothesis = _make_eligible_etf_hypothesis(demo_period_days=29)
        assert policy.check_auto_eligibility(hypothesis, partner_restricted_symbols=[]) is False

    def test_requires_compliance_review_returns_false(self) -> None:
        policy = PromotionEligibilityPolicy()
        hypothesis = _make_eligible_etf_hypothesis(requires_compliance_review=True)
        assert policy.check_auto_eligibility(hypothesis, partner_restricted_symbols=[]) is False

    def test_instrument_type_stock_returns_false(self) -> None:
        policy = PromotionEligibilityPolicy()
        demo_window = DemoWindow(
            started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
            ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.UTC),
            demo_period_days=30,
        )
        hypothesis = Hypothesis(
            identifier="01JNPQRS000000000000000020",
            symbol="7203",
            instrument_type=InstrumentType.STOCK,
            status=HypothesisStatus.DEMO,
            title="Stock hypothesis",
            source_evidence=["insight-001"],
            skill_version="v1.0.0",
            instruction_profile_version="v1.0.0",
            updated_at=_NOW,
            insider_risk=InsiderRisk.LOW,
            requires_compliance_review=False,
            mnpi_self_declared=True,
            auto_promotion_eligible=True,
            demo_window=demo_window,
        )
        assert policy.check_auto_eligibility(hypothesis, partner_restricted_symbols=[]) is False

    def test_insider_risk_medium_returns_false(self) -> None:
        policy = PromotionEligibilityPolicy()
        hypothesis = _make_eligible_etf_hypothesis(insider_risk=InsiderRisk.MEDIUM)
        assert policy.check_auto_eligibility(hypothesis, partner_restricted_symbols=[]) is False

    def test_insider_risk_high_returns_false(self) -> None:
        policy = PromotionEligibilityPolicy()
        hypothesis = _make_eligible_etf_hypothesis(insider_risk=InsiderRisk.HIGH)
        assert policy.check_auto_eligibility(hypothesis, partner_restricted_symbols=[]) is False

    def test_mnpi_self_declared_false_returns_false(self) -> None:
        policy = PromotionEligibilityPolicy()
        hypothesis = _make_eligible_etf_hypothesis(mnpi_self_declared=False)
        assert policy.check_auto_eligibility(hypothesis, partner_restricted_symbols=[]) is False

    def test_symbol_in_partner_restricted_returns_false(self) -> None:
        policy = PromotionEligibilityPolicy()
        hypothesis = _make_eligible_etf_hypothesis(symbol="RESTRICTED")
        assert policy.check_auto_eligibility(hypothesis, partner_restricted_symbols=["RESTRICTED"]) is False

    def test_no_demo_window_returns_false(self) -> None:
        policy = PromotionEligibilityPolicy()
        hypothesis = Hypothesis(
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
            requires_compliance_review=False,
            mnpi_self_declared=True,
            demo_window=None,
        )
        assert policy.check_auto_eligibility(hypothesis, partner_restricted_symbols=[]) is False
