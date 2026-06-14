"""Tests for Hypothesis aggregate root (Must-E-01..Must-E-03, Must-S-01..Must-S-05)."""

from __future__ import annotations

import datetime

import pytest

from domain.event.domain_events import HypothesisBacktested, HypothesisPromoted, HypothesisRejected
from domain.model.hypothesis import Hypothesis
from domain.value_object.demo_window import DemoWindow
from domain.value_object.enums import (
    HypothesisStatus,
    InsiderRisk,
    InstrumentType,
    PromotionDecisionType,
    PromotionMode,
    ReasonCode,
)
from domain.value_object.performance_metrics import PerformanceMetrics
from domain.value_object.promotion_decision import PromotionDecision

_NOW = datetime.datetime(2026, 3, 1, tzinfo=datetime.UTC)
_TRACE = "01JNPQRS000000000000000001"
_VALIDATION_RUN_IDENTIFIER = "01JNPQRS000000000000000002"


def _make_draft_etf_hypothesis(
    identifier: str = "01JNPQRS000000000000000010",
    symbol: str = "1234",
    insider_risk: InsiderRisk | None = InsiderRisk.LOW,
    requires_compliance_review: bool | None = False,
    mnpi_self_declared: bool | None = True,
) -> Hypothesis:
    return Hypothesis(
        identifier=identifier,
        symbol=symbol,
        instrument_type=InstrumentType.ETF,
        status=HypothesisStatus.DRAFT,
        title="Test ETF hypothesis",
        source_evidence=["insight-001", "insight-002"],
        skill_version="v1.0.0",
        instruction_profile_version="v1.0.0",
        updated_at=_NOW,
        insider_risk=insider_risk,
        requires_compliance_review=requires_compliance_review,
        mnpi_self_declared=mnpi_self_declared,
    )


def _make_demo_etf_hypothesis(
    identifier: str = "01JNPQRS000000000000000010",
    symbol: str = "1234",
    insider_risk: InsiderRisk = InsiderRisk.LOW,
    requires_compliance_review: bool = False,
    mnpi_self_declared: bool = True,
) -> Hypothesis:
    return Hypothesis(
        identifier=identifier,
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
    )


def _make_demo_stock_hypothesis(
    identifier: str = "01JNPQRS000000000000000020",
    symbol: str = "7203",
    insider_risk: InsiderRisk = InsiderRisk.LOW,
    requires_compliance_review: bool = False,
    mnpi_self_declared: bool = True,
) -> Hypothesis:
    return Hypothesis(
        identifier=identifier,
        symbol=symbol,
        instrument_type=InstrumentType.STOCK,
        status=HypothesisStatus.DEMO,
        title="Test STOCK hypothesis",
        source_evidence=["insight-001"],
        skill_version="v1.0.0",
        instruction_profile_version="v1.0.0",
        updated_at=_NOW,
        insider_risk=insider_risk,
        requires_compliance_review=requires_compliance_review,
        mnpi_self_declared=mnpi_self_declared,
    )


def _make_metrics() -> PerformanceMetrics:
    return PerformanceMetrics(cost_adjusted_return=0.12, dsr=1.5, pbo=0.05)


def _make_demo_window(demo_period_days: int = 30) -> DemoWindow:
    return DemoWindow(
        started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.UTC),
        demo_period_days=demo_period_days,
    )


class TestHypothesisCreation:
    """Must-E-01: Required fields are present."""

    def test_all_required_fields_set(self) -> None:
        hypothesis = _make_draft_etf_hypothesis()
        assert hypothesis.identifier == "01JNPQRS000000000000000010"
        assert hypothesis.symbol == "1234"
        assert hypothesis.instrument_type == InstrumentType.ETF
        assert hypothesis.status == HypothesisStatus.DRAFT
        assert hypothesis.title == "Test ETF hypothesis"
        assert hypothesis.source_evidence == ["insight-001", "insight-002"]
        assert hypothesis.skill_version == "v1.0.0"
        assert hypothesis.instruction_profile_version == "v1.0.0"
        assert hypothesis.updated_at == _NOW

    def test_rejects_empty_identifier(self) -> None:
        with pytest.raises(ValueError):
            Hypothesis(
                identifier="",
                symbol="1234",
                instrument_type=InstrumentType.ETF,
                status=HypothesisStatus.DRAFT,
                title="Title",
                source_evidence=["e1"],
                skill_version="v1",
                instruction_profile_version="v1",
                updated_at=_NOW,
            )

    def test_rejects_empty_title(self) -> None:
        with pytest.raises(ValueError, match="title"):
            Hypothesis(
                identifier="01JNPQRS000000000000000010",
                symbol="1234",
                instrument_type=InstrumentType.ETF,
                status=HypothesisStatus.DRAFT,
                title="",
                source_evidence=["e1"],
                skill_version="v1",
                instruction_profile_version="v1",
                updated_at=_NOW,
            )

    def test_rejects_empty_source_evidence(self) -> None:
        with pytest.raises(ValueError, match="source_evidence"):
            Hypothesis(
                identifier="01JNPQRS000000000000000010",
                symbol="1234",
                instrument_type=InstrumentType.ETF,
                status=HypothesisStatus.DRAFT,
                title="Title",
                source_evidence=[],
                skill_version="v1",
                instruction_profile_version="v1",
                updated_at=_NOW,
            )

    def test_rejects_empty_skill_version(self) -> None:
        with pytest.raises(ValueError, match="skill_version"):
            Hypothesis(
                identifier="01JNPQRS000000000000000010",
                symbol="1234",
                instrument_type=InstrumentType.ETF,
                status=HypothesisStatus.DRAFT,
                title="Title",
                source_evidence=["e1"],
                skill_version="",
                instruction_profile_version="v1",
                updated_at=_NOW,
            )

    def test_rejects_empty_instruction_profile_version(self) -> None:
        with pytest.raises(ValueError, match="instruction_profile_version"):
            Hypothesis(
                identifier="01JNPQRS000000000000000010",
                symbol="1234",
                instrument_type=InstrumentType.ETF,
                status=HypothesisStatus.DRAFT,
                title="Title",
                source_evidence=["e1"],
                skill_version="v1",
                instruction_profile_version="",
                updated_at=_NOW,
            )

    def test_no_domain_events_on_construction(self) -> None:
        hypothesis = _make_draft_etf_hypothesis()
        assert hypothesis.domain_events == []


class TestHypothesisIdentifierImmutability:
    """Must-E-02: identifier is immutable."""

    def test_identifier_cannot_be_reassigned(self) -> None:
        hypothesis = _make_draft_etf_hypothesis()
        with pytest.raises(AttributeError):
            hypothesis.identifier = "new-identifier"  # type: ignore[misc]


class TestHypothesisMethods:
    """Must-E-03: Four public methods exist."""

    def test_has_apply_backtest_result_method(self) -> None:
        hypothesis = _make_draft_etf_hypothesis()
        assert callable(hypothesis.apply_backtest_result)

    def test_has_apply_demo_result_method(self) -> None:
        hypothesis = _make_demo_etf_hypothesis()
        assert callable(hypothesis.apply_demo_result)

    def test_has_promote_method(self) -> None:
        hypothesis = _make_demo_etf_hypothesis()
        assert callable(hypothesis.promote)

    def test_has_reject_method(self) -> None:
        hypothesis = _make_demo_etf_hypothesis()
        assert callable(hypothesis.reject)


class TestBacktestResult:
    """Must-S-01: RULE-HL-001 — backtest pass=false -> rejected."""

    def test_backtest_pass_true_transitions_to_backtested(self) -> None:
        hypothesis = _make_draft_etf_hypothesis()
        result = hypothesis.apply_backtest_result(
            passed=True,
            performance_metrics=_make_metrics(),
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert result is None
        assert hypothesis.status == HypothesisStatus.BACKTESTED

    def test_backtest_pass_false_transitions_to_rejected(self) -> None:
        """TST-HL-001: RecordBacktestResult(pass=false) -> rejected."""
        hypothesis = _make_draft_etf_hypothesis()
        result = hypothesis.apply_backtest_result(
            passed=False,
            performance_metrics=_make_metrics(),
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert result is None
        assert hypothesis.status == HypothesisStatus.REJECTED

    def test_backtest_pass_false_does_not_transition_to_backtested(self) -> None:
        hypothesis = _make_draft_etf_hypothesis()
        hypothesis.apply_backtest_result(
            passed=False,
            performance_metrics=_make_metrics(),
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert hypothesis.status != HypothesisStatus.BACKTESTED

    def test_backtest_pass_false_does_not_transition_to_demo(self) -> None:
        hypothesis = _make_draft_etf_hypothesis()
        hypothesis.apply_backtest_result(
            passed=False,
            performance_metrics=_make_metrics(),
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert hypothesis.status != HypothesisStatus.DEMO

    def test_backtest_emits_hypothesis_backtested_event(self) -> None:
        """Must-DE-01: HypothesisBacktested event emitted."""
        hypothesis = _make_draft_etf_hypothesis()
        hypothesis.apply_backtest_result(
            passed=True,
            performance_metrics=_make_metrics(),
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        events = hypothesis.domain_events
        backtest_events = [e for e in events if isinstance(e, HypothesisBacktested)]
        assert len(backtest_events) == 1
        event = backtest_events[0]
        assert event.identifier == hypothesis.identifier
        assert event.passed is True
        assert event.cost_adjusted_return == 0.12
        assert event.dsr == 1.5
        assert event.pbo == 0.05

    def test_backtest_fail_emits_rejected_event(self) -> None:
        """Must-DE-03: HypothesisRejected event emitted on backtest fail."""
        hypothesis = _make_draft_etf_hypothesis()
        hypothesis.apply_backtest_result(
            passed=False,
            performance_metrics=_make_metrics(),
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        events = hypothesis.domain_events
        rejected_events = [e for e in events if isinstance(e, HypothesisRejected)]
        assert len(rejected_events) == 1

    def test_backtest_on_non_draft_returns_state_conflict(self) -> None:
        hypothesis = _make_demo_etf_hypothesis()
        result = hypothesis.apply_backtest_result(
            passed=True,
            performance_metrics=_make_metrics(),
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert result == ReasonCode.STATE_CONFLICT

    def test_backtest_idempotent_on_already_backtested(self) -> None:
        hypothesis = _make_draft_etf_hypothesis()
        hypothesis.apply_backtest_result(
            passed=True,
            performance_metrics=_make_metrics(),
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        result = hypothesis.apply_backtest_result(
            passed=True,
            performance_metrics=_make_metrics(),
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert result == ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT


class TestDemoResult:
    """Must-S-02, Must-S-03: auto-promote conditions and STOCK restriction."""

    def test_auto_promote_when_all_conditions_met_etf(self) -> None:
        """TST-HL-002/003: all 7 auto-promote conditions satisfied -> live."""
        hypothesis = _make_demo_etf_hypothesis(
            symbol="not-restricted",
            insider_risk=InsiderRisk.LOW,
            requires_compliance_review=False,
            mnpi_self_declared=True,
        )
        result = hypothesis.apply_demo_result(
            demo_window=_make_demo_window(demo_period_days=30),
            promotable=True,
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            partner_restricted_symbols=[],
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert result is None
        assert hypothesis.status == HypothesisStatus.LIVE

    def test_auto_promote_emits_promoted_event(self) -> None:
        """Must-DE-02: HypothesisPromoted event emitted on auto-promote."""
        hypothesis = _make_demo_etf_hypothesis(
            insider_risk=InsiderRisk.LOW,
            requires_compliance_review=False,
            mnpi_self_declared=True,
        )
        hypothesis.apply_demo_result(
            demo_window=_make_demo_window(30),
            promotable=True,
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            partner_restricted_symbols=[],
            trace=_TRACE,
            occurred_at=_NOW,
        )
        events = hypothesis.domain_events
        promoted_events = [e for e in events if isinstance(e, HypothesisPromoted)]
        assert len(promoted_events) == 1
        event = promoted_events[0]
        assert event.identifier == hypothesis.identifier
        assert event.promotion_mode == PromotionMode.AUTO

    def test_no_auto_promote_when_demo_period_days_less_than_30(self) -> None:
        """TST-HL-002: demoPeriodDays < 30 -> stays demo."""
        hypothesis = _make_demo_etf_hypothesis(
            insider_risk=InsiderRisk.LOW,
            requires_compliance_review=False,
            mnpi_self_declared=True,
        )
        result = hypothesis.apply_demo_result(
            demo_window=_make_demo_window(demo_period_days=29),
            promotable=True,
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            partner_restricted_symbols=[],
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert result is None
        assert hypothesis.status == HypothesisStatus.DEMO

    def test_no_auto_promote_when_requires_compliance_review(self) -> None:
        hypothesis = _make_demo_etf_hypothesis(
            insider_risk=InsiderRisk.LOW,
            requires_compliance_review=True,
            mnpi_self_declared=True,
        )
        hypothesis.apply_demo_result(
            demo_window=_make_demo_window(30),
            promotable=True,
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            partner_restricted_symbols=[],
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert hypothesis.status == HypothesisStatus.DEMO

    def test_no_auto_promote_when_instrument_type_is_stock(self) -> None:
        """TST-HL-004: STOCK type does not auto-promote (RULE-HL-004)."""
        hypothesis = _make_demo_stock_hypothesis(
            insider_risk=InsiderRisk.LOW,
            requires_compliance_review=False,
            mnpi_self_declared=True,
        )
        result = hypothesis.apply_demo_result(
            demo_window=_make_demo_window(30),
            promotable=True,
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            partner_restricted_symbols=[],
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert result is None
        assert hypothesis.status == HypothesisStatus.DEMO

    def test_no_auto_promote_when_insider_risk_is_not_low(self) -> None:
        hypothesis = _make_demo_etf_hypothesis(
            insider_risk=InsiderRisk.MEDIUM,
            requires_compliance_review=False,
            mnpi_self_declared=True,
        )
        hypothesis.apply_demo_result(
            demo_window=_make_demo_window(30),
            promotable=True,
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            partner_restricted_symbols=[],
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert hypothesis.status == HypothesisStatus.DEMO

    def test_no_auto_promote_when_mnpi_self_declared_is_false(self) -> None:
        hypothesis = _make_demo_etf_hypothesis(
            insider_risk=InsiderRisk.LOW,
            requires_compliance_review=False,
            mnpi_self_declared=False,
        )
        hypothesis.apply_demo_result(
            demo_window=_make_demo_window(30),
            promotable=True,
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            partner_restricted_symbols=[],
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert hypothesis.status == HypothesisStatus.DEMO

    def test_no_auto_promote_when_symbol_in_partner_restricted_symbols(self) -> None:
        hypothesis = _make_demo_etf_hypothesis(
            symbol="RESTRICTED-ETF",
            insider_risk=InsiderRisk.LOW,
            requires_compliance_review=False,
            mnpi_self_declared=True,
        )
        hypothesis.apply_demo_result(
            demo_window=_make_demo_window(30),
            promotable=True,
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            partner_restricted_symbols=["RESTRICTED-ETF"],
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert hypothesis.status == HypothesisStatus.DEMO

    def test_rejected_when_promotable_is_false(self) -> None:
        hypothesis = _make_demo_etf_hypothesis()
        hypothesis.apply_demo_result(
            demo_window=_make_demo_window(30),
            promotable=False,
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            partner_restricted_symbols=[],
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert hypothesis.status == HypothesisStatus.REJECTED

    def test_demo_result_on_non_demo_returns_state_conflict(self) -> None:
        hypothesis = _make_draft_etf_hypothesis()
        result = hypothesis.apply_demo_result(
            demo_window=_make_demo_window(30),
            promotable=True,
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            partner_restricted_symbols=[],
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert result == ReasonCode.STATE_CONFLICT


class TestManualPromotion:
    """Must-S-03: STOCK can be manually promoted."""

    def test_manual_promote_stock_hypothesis_to_live(self) -> None:
        """TST-HL-004: PromoteHypothesis command -> live for STOCK."""
        hypothesis = _make_demo_stock_hypothesis(
            requires_compliance_review=False,
        )
        decision = PromotionDecision(
            decision=PromotionDecisionType.PROMOTED,
            action_reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            promotion_mode=PromotionMode.MANUAL,
        )
        result = hypothesis.promote(
            promotion_decision=decision,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert result is None
        assert hypothesis.status == HypothesisStatus.LIVE

    def test_manual_promote_emits_promoted_event(self) -> None:
        hypothesis = _make_demo_etf_hypothesis(requires_compliance_review=False)
        decision = PromotionDecision(
            decision=PromotionDecisionType.PROMOTED,
            action_reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            promotion_mode=PromotionMode.MANUAL,
        )
        hypothesis.promote(promotion_decision=decision, trace=_TRACE, occurred_at=_NOW)
        promoted_events = [e for e in hypothesis.domain_events if isinstance(e, HypothesisPromoted)]
        assert len(promoted_events) == 1

    def test_promote_from_non_demo_returns_state_conflict(self) -> None:
        hypothesis = _make_draft_etf_hypothesis()
        decision = PromotionDecision(
            decision=PromotionDecisionType.PROMOTED,
            action_reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            promotion_mode=PromotionMode.MANUAL,
        )
        result = hypothesis.promote(promotion_decision=decision, trace=_TRACE, occurred_at=_NOW)
        assert result == ReasonCode.STATE_CONFLICT

    def test_promote_with_compliance_review_required_returns_error(self) -> None:
        hypothesis = _make_demo_etf_hypothesis(requires_compliance_review=True)
        decision = PromotionDecision(
            decision=PromotionDecisionType.PROMOTED,
            action_reason_code=ReasonCode.COMPLIANCE_REVIEW_REQUIRED,
            promotion_mode=PromotionMode.MANUAL,
        )
        result = hypothesis.promote(promotion_decision=decision, trace=_TRACE, occurred_at=_NOW)
        assert result == ReasonCode.COMPLIANCE_REVIEW_REQUIRED


class TestManualRejection:
    def test_reject_from_demo_transitions_to_rejected(self) -> None:
        hypothesis = _make_demo_etf_hypothesis()
        decision = PromotionDecision(
            decision=PromotionDecisionType.REJECTED,
            action_reason_code=ReasonCode.OPERATION_NOT_ALLOWED,
            promotion_mode=PromotionMode.MANUAL,
        )
        result = hypothesis.reject(promotion_decision=decision, trace=_TRACE, occurred_at=_NOW)
        assert result is None
        assert hypothesis.status == HypothesisStatus.REJECTED

    def test_reject_emits_rejected_event(self) -> None:
        """Must-DE-03: HypothesisRejected event emitted."""
        hypothesis = _make_demo_etf_hypothesis()
        decision = PromotionDecision(
            decision=PromotionDecisionType.REJECTED,
            action_reason_code=ReasonCode.OPERATION_NOT_ALLOWED,
            promotion_mode=PromotionMode.MANUAL,
        )
        hypothesis.reject(promotion_decision=decision, trace=_TRACE, occurred_at=_NOW)
        rejected_events = [e for e in hypothesis.domain_events if isinstance(e, HypothesisRejected)]
        assert len(rejected_events) == 1
        event = rejected_events[0]
        assert event.identifier == hypothesis.identifier
        assert event.promotion_mode == PromotionMode.MANUAL

    def test_reject_from_non_demo_returns_state_conflict(self) -> None:
        hypothesis = _make_draft_etf_hypothesis()
        decision = PromotionDecision(
            decision=PromotionDecisionType.REJECTED,
            action_reason_code=ReasonCode.OPERATION_NOT_ALLOWED,
            promotion_mode=PromotionMode.MANUAL,
        )
        result = hypothesis.reject(promotion_decision=decision, trace=_TRACE, occurred_at=_NOW)
        assert result == ReasonCode.STATE_CONFLICT


class TestMnpiSelfDeclaration:
    """Must-S-04: RULE-HL-008 — only allowed when status=demo."""

    def test_update_mnpi_self_declaration_in_demo_status(self) -> None:
        hypothesis = _make_demo_etf_hypothesis(mnpi_self_declared=False)
        result = hypothesis.update_mnpi_self_declaration(value=True, occurred_at=_NOW)
        assert result is None
        assert hypothesis.mnpi_self_declared is True

    @pytest.mark.parametrize(
        "status",
        [
            HypothesisStatus.DRAFT,
            HypothesisStatus.BACKTESTED,
            HypothesisStatus.LIVE,
            HypothesisStatus.REJECTED,
        ],
    )
    def test_update_mnpi_self_declaration_rejects_non_demo_status(self, status: HypothesisStatus) -> None:
        """TST-HL-005: OPERATION_NOT_ALLOWED for non-demo statuses."""
        hypothesis = Hypothesis(
            identifier="01JNPQRS000000000000000010",
            symbol="1234",
            instrument_type=InstrumentType.ETF,
            status=status,
            title="Title",
            source_evidence=["e1"],
            skill_version="v1",
            instruction_profile_version="v1",
            updated_at=_NOW,
        )
        result = hypothesis.update_mnpi_self_declaration(value=True, occurred_at=_NOW)
        assert result == ReasonCode.OPERATION_NOT_ALLOWED


class TestImmutableRequiredFields:
    """Must-S-05: RULE-HL-009 — required fields cannot be nullified."""

    def test_required_fields_persist_after_backtest(self) -> None:
        """TST-HL-010: title, source_evidence, skill_version, instruction_profile_version retained."""
        hypothesis = _make_draft_etf_hypothesis()
        hypothesis.apply_backtest_result(
            passed=True,
            performance_metrics=_make_metrics(),
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert hypothesis.title == "Test ETF hypothesis"
        assert hypothesis.source_evidence == ["insight-001", "insight-002"]
        assert hypothesis.skill_version == "v1.0.0"
        assert hypothesis.instruction_profile_version == "v1.0.0"


class TestDomainEventEnvelope:
    """Must-DE-04: event identifier is ULID format (26 chars)."""

    def test_hypothesis_identifier_in_event_is_set(self) -> None:
        hypothesis = _make_draft_etf_hypothesis(identifier="01JNPQRS000000000000000010")
        hypothesis.apply_backtest_result(
            passed=True,
            performance_metrics=_make_metrics(),
            validation_run_identifier=_VALIDATION_RUN_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        events = hypothesis.domain_events
        assert len(events) > 0
        event = events[0]
        assert isinstance(event, HypothesisBacktested)
        # The hypothesis identifier in the event
        assert event.identifier == "01JNPQRS000000000000000010"
