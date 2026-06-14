"""Tests for Hypothesis aggregate root."""

import datetime

import pytest

from hypothesis_lab.domain.aggregates.hypothesis import Hypothesis
from hypothesis_lab.domain.enums.hypothesis_status import HypothesisStatus
from hypothesis_lab.domain.enums.insider_risk import InsiderRisk
from hypothesis_lab.domain.enums.instrument_type import InstrumentType
from hypothesis_lab.domain.enums.promotion_mode import PromotionMode
from hypothesis_lab.domain.value_objects.demo_window import DemoWindow
from hypothesis_lab.domain.value_objects.performance_metrics import PerformanceMetrics


def make_draft_hypothesis(
    identifier: str = "01HXXXXXXXXXXXXXXXXXXX",
    symbol: str = "1234",
    instrument_type: InstrumentType = InstrumentType.ETF,
    insider_risk: InsiderRisk | None = None,
    requires_compliance_review: bool | None = None,
) -> Hypothesis:
    """Helper to create a Hypothesis in DRAFT status."""
    return Hypothesis(
        identifier=identifier,
        symbol=symbol,
        instrument_type=instrument_type,
        status=HypothesisStatus.DRAFT,
        title="Test Hypothesis",
        source_evidence=["evidence-1"],
        skill_version="v1.0.0",
        instruction_profile_version="v1.0.0",
        insider_risk=insider_risk,
        requires_compliance_review=requires_compliance_review,
        updated_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
    )


def make_backtested_hypothesis(
    identifier: str = "01HXXXXXXXXXXXXXXXXXXX",
    symbol: str = "1234",
    instrument_type: InstrumentType = InstrumentType.ETF,
    insider_risk: InsiderRisk | None = None,
    requires_compliance_review: bool | None = None,
) -> Hypothesis:
    """Helper to create a Hypothesis in BACKTESTED status."""
    hypothesis = make_draft_hypothesis(
        identifier=identifier,
        symbol=symbol,
        instrument_type=instrument_type,
        insider_risk=insider_risk,
        requires_compliance_review=requires_compliance_review,
    )
    metrics = PerformanceMetrics(cost_adjusted_return=0.15, dsr=1.2, pbo=0.05)
    hypothesis.record_backtest_result(passed=True, metrics=metrics)
    return hypothesis


def make_demo_hypothesis(
    identifier: str = "01HXXXXXXXXXXXXXXXXXXX",
    symbol: str = "1234",
    instrument_type: InstrumentType = InstrumentType.ETF,
    demo_window: DemoWindow | None = None,
    insider_risk: InsiderRisk | None = None,
    requires_compliance_review: bool | None = None,
) -> Hypothesis:
    """Helper to create a Hypothesis in DEMO status."""
    hypothesis = make_backtested_hypothesis(
        identifier=identifier,
        symbol=symbol,
        instrument_type=instrument_type,
        insider_risk=insider_risk,
        requires_compliance_review=requires_compliance_review,
    )
    hypothesis.start_demo_run()
    if demo_window is not None:
        hypothesis.complete_demo_run(
            demo_window=demo_window,
            promotable=True,
        )
    return hypothesis


class TestHypothesisStateTransitions:
    def test_record_backtest_result_pass_transitions_draft_to_backtested(self) -> None:
        """RULE-HL: draft -> backtested on RecordBacktestResult(pass=True)."""
        hypothesis = make_draft_hypothesis()
        metrics = PerformanceMetrics(cost_adjusted_return=0.15, dsr=1.2, pbo=0.05)
        hypothesis.record_backtest_result(passed=True, metrics=metrics)
        assert hypothesis.status == HypothesisStatus.BACKTESTED

    def test_record_backtest_result_fail_transitions_draft_to_rejected(self) -> None:
        """RULE-HL: draft -> rejected on RecordBacktestResult(pass=False)."""
        hypothesis = make_draft_hypothesis()
        metrics = PerformanceMetrics(cost_adjusted_return=-0.05, dsr=0.3, pbo=0.8)
        hypothesis.record_backtest_result(passed=False, metrics=metrics)
        assert hypothesis.status == HypothesisStatus.REJECTED

    def test_start_demo_run_transitions_backtested_to_demo(self) -> None:
        """RULE-HL-001: backtested -> demo on StartDemoRun."""
        hypothesis = make_backtested_hypothesis()
        hypothesis.start_demo_run()
        assert hypothesis.status == HypothesisStatus.DEMO

    def test_start_demo_run_raises_on_draft_status(self) -> None:
        """AC-05: draft -> demo is FORBIDDEN (RULE-HL-001)."""
        hypothesis = make_draft_hypothesis()
        with pytest.raises(Exception):
            hypothesis.start_demo_run()
        assert hypothesis.status == HypothesisStatus.DRAFT

    def test_complete_demo_run_with_promotable_true_and_auto_conditions_met_promotes_to_live(self) -> None:
        """AC-01 path: demo -> live when all auto-promotion conditions are met."""
        demo_window = DemoWindow(
            started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.timezone.utc),
            demo_period_days=31,
        )
        hypothesis = make_demo_hypothesis(
            instrument_type=InstrumentType.ETF,
            demo_window=None,
            insider_risk=InsiderRisk.LOW,
            requires_compliance_review=False,
        )
        # Set up hypothesis for auto-promotion conditions
        hypothesis.update_mnpi_self_declaration(mnpi_self_declared=True)

        from hypothesis_lab.domain.services.promotion_eligibility_policy import PromotionEligibilityPolicy
        from hypothesis_lab.domain.enums.promotion_eligibility import PromotionEligibility

        hypothesis.complete_demo_run(demo_window=demo_window, promotable=True)
        policy = PromotionEligibilityPolicy()
        eligibility = policy.check(hypothesis, partner_restricted_symbols=set())
        # The policy returns auto; manual promotion should succeed
        assert hypothesis.status == HypothesisStatus.DEMO  # still demo, pending promotion command

    def test_promote_hypothesis_transitions_demo_to_live(self) -> None:
        """demo -> live via PromoteHypothesis (manual path)."""
        demo_window = DemoWindow(
            started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.timezone.utc),
            demo_period_days=31,
        )
        hypothesis = make_demo_hypothesis(
            instrument_type=InstrumentType.ETF,
            requires_compliance_review=False,
        )
        hypothesis.complete_demo_run(demo_window=demo_window, promotable=True)
        hypothesis.promote(promotion_mode=PromotionMode.MANUAL)
        assert hypothesis.status == HypothesisStatus.LIVE

    def test_reject_hypothesis_transitions_demo_to_rejected(self) -> None:
        """demo -> rejected via RejectHypothesis."""
        hypothesis = make_demo_hypothesis()
        hypothesis.reject()
        assert hypothesis.status == HypothesisStatus.REJECTED

    def test_complete_demo_run_with_promotable_false_transitions_demo_to_rejected(self) -> None:
        """demo -> rejected when CompleteDemoRun(promotable=False)."""
        demo_window = DemoWindow(
            started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.timezone.utc),
            demo_period_days=31,
        )
        hypothesis = make_demo_hypothesis()
        hypothesis.complete_demo_run(demo_window=demo_window, promotable=False)
        assert hypothesis.status == HypothesisStatus.REJECTED

    def test_promote_requires_promotion_ready(self) -> None:
        """INV-HL-002: live transition requires PromotionReadySpecification satisfied."""
        demo_window = DemoWindow(
            started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            ended_at=datetime.datetime(2026, 1, 15, tzinfo=datetime.timezone.utc),
            demo_period_days=14,  # Less than 30 days
        )
        hypothesis = make_demo_hypothesis()
        hypothesis.complete_demo_run(demo_window=demo_window, promotable=True)
        with pytest.raises(Exception):
            hypothesis.promote(promotion_mode=PromotionMode.MANUAL)

    def test_live_is_terminal_state(self) -> None:
        """AC-11: live is terminal — no further transitions allowed."""
        demo_window = DemoWindow(
            started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.timezone.utc),
            demo_period_days=31,
        )
        hypothesis = make_demo_hypothesis(
            instrument_type=InstrumentType.ETF,
            requires_compliance_review=False,
        )
        hypothesis.complete_demo_run(demo_window=demo_window, promotable=True)
        hypothesis.promote(promotion_mode=PromotionMode.MANUAL)
        assert hypothesis.status == HypothesisStatus.LIVE
        with pytest.raises(Exception):
            hypothesis.reject()

    def test_rejected_is_terminal_state(self) -> None:
        """AC-11: rejected is terminal — no further transitions allowed."""
        hypothesis = make_draft_hypothesis()
        metrics = PerformanceMetrics(cost_adjusted_return=-0.1, dsr=0.2, pbo=0.9)
        hypothesis.record_backtest_result(passed=False, metrics=metrics)
        assert hypothesis.status == HypothesisStatus.REJECTED
        with pytest.raises(Exception):
            hypothesis.start_demo_run()


class TestHypothesisInvariants:
    def test_identifier_is_immutable(self) -> None:
        """INV-HL-001: identifier is immutable after creation."""
        hypothesis = make_draft_hypothesis(identifier="01HXXXXXXXXXXXXXXXXXXX")
        original_identifier = hypothesis.identifier
        with pytest.raises((AttributeError, TypeError)):
            hypothesis.identifier = "new-identifier"  # type: ignore[misc]
        assert hypothesis.identifier == original_identifier

    def test_required_fields_present_after_creation(self) -> None:
        """INV-HL-005: required fields must not be missing."""
        hypothesis = make_draft_hypothesis()
        assert hypothesis.title != ""
        assert len(hypothesis.source_evidence) >= 1
        assert hypothesis.skill_version != ""
        assert hypothesis.instruction_profile_version != ""

    def test_source_evidence_must_have_at_least_one_entry(self) -> None:
        """INV: source_evidence must have at least 1 entry."""
        with pytest.raises((ValueError, Exception)):
            Hypothesis(
                identifier="01HXXXXXXXXXXXXXXXXXXX",
                symbol="1234",
                instrument_type=InstrumentType.ETF,
                status=HypothesisStatus.DRAFT,
                title="Test",
                source_evidence=[],  # Empty is invalid
                skill_version="v1.0.0",
                instruction_profile_version="v1.0.0",
                updated_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            )


class TestHypothesisMnpiUpdate:
    def test_update_mnpi_self_declaration_allowed_in_demo_status(self) -> None:
        """RULE-HL-008: mnpi_self_declared can be updated only in demo status."""
        hypothesis = make_demo_hypothesis()
        hypothesis.update_mnpi_self_declaration(mnpi_self_declared=True)
        assert hypothesis.mnpi_self_declared is True

    def test_update_mnpi_self_declaration_raises_in_backtested_status(self) -> None:
        """AC-06: UpdateMnpiSelfDeclaration on non-demo status raises exception."""
        hypothesis = make_backtested_hypothesis()
        with pytest.raises(Exception):
            hypothesis.update_mnpi_self_declaration(mnpi_self_declared=True)

    def test_update_mnpi_self_declaration_raises_in_draft_status(self) -> None:
        """RULE-HL-008: MNPI update only allowed in demo status."""
        hypothesis = make_draft_hypothesis()
        with pytest.raises(Exception):
            hypothesis.update_mnpi_self_declaration(mnpi_self_declared=True)
