"""Hypothesis aggregate root."""

from __future__ import annotations

import datetime
import re

from domain.event.domain_events import HypothesisBacktested, HypothesisPromoted, HypothesisRejected
from domain.value_object.demo_window import DemoWindow
from domain.value_object.enums import (
    HypothesisStatus,
    InsiderRisk,
    InstrumentType,
    PromotionDecisionType,
    PromotionMode,
    ReasonCode,
)
from domain.value_object.failure_summary import FailureSummary
from domain.value_object.performance_metrics import PerformanceMetrics
from domain.value_object.promotion_decision import PromotionDecision

# Type alias for identifiers
HypothesisIdentifier = str
ValidationRunIdentifier = str

DomainEvent = HypothesisBacktested | HypothesisPromoted | HypothesisRejected

_ULID_PATTERN = re.compile(r"[0-9A-HJKMNP-TV-Z]{26}")


class Hypothesis:
    """Aggregate root managing the lifecycle of an investment hypothesis.

    Enforces invariants:
    - INV-HL-001: identifier is immutable after construction.
    - INV-HL-002: live transition requires full promotion conditions.
    - INV-HL-003: auto-promotion requires ETF + low insider risk + MNPI self-declared
                  + symbol not in partner restricted symbols.
    - INV-HL-005: title, source_evidence, skill_version, instruction_profile_version
                  are always retained.

    State transitions (§5.1):
      draft -> backtested (backtest pass=true)
      draft -> rejected   (backtest pass=false)
      backtested -> demo  (start demo run - outside domain layer, status set externally)
      demo -> live        (auto-promote when all conditions met)
      demo -> demo        (demo completed but auto-promote conditions not met)
      demo -> rejected    (promotable=false OR manual reject)
      demo -> live        (manual promote)
    """

    def __init__(
        self,
        identifier: HypothesisIdentifier,
        symbol: str,
        instrument_type: InstrumentType,
        status: HypothesisStatus,
        title: str,
        source_evidence: list[str],
        skill_version: str,
        instruction_profile_version: str,
        updated_at: datetime.datetime,
        insider_risk: InsiderRisk | None = None,
        requires_compliance_review: bool | None = None,
        mnpi_self_declared: bool | None = None,
        auto_promotion_eligible: bool | None = None,
        promotion_mode: PromotionMode | None = None,
        latest_failure_summary: FailureSummary | None = None,
        performance_metrics: PerformanceMetrics | None = None,
        demo_window: DemoWindow | None = None,
    ) -> None:
        # INV-HL-001: identifier must be non-empty
        if not identifier:
            raise ValueError("identifier must not be empty")

        # INV-HL-005: immutable required fields must always be present
        if not title:
            raise ValueError("INV-HL-005: title must not be empty")
        if not source_evidence:
            raise ValueError("INV-HL-005: source_evidence must not be empty")
        if not skill_version:
            raise ValueError("INV-HL-005: skill_version must not be empty")
        if not instruction_profile_version:
            raise ValueError("INV-HL-005: instruction_profile_version must not be empty")

        self._identifier = identifier
        self._symbol = symbol
        self._instrument_type = instrument_type
        self._status = status
        self._title = title
        self._source_evidence: list[str] = list(source_evidence)
        self._skill_version = skill_version
        self._instruction_profile_version = instruction_profile_version
        self._updated_at = updated_at
        self._insider_risk = insider_risk
        self._requires_compliance_review = requires_compliance_review
        self._mnpi_self_declared = mnpi_self_declared
        self._auto_promotion_eligible = auto_promotion_eligible
        self._promotion_mode = promotion_mode
        self._latest_failure_summary = latest_failure_summary
        self._performance_metrics = performance_metrics
        self._demo_window = demo_window
        self._domain_events: list[DomainEvent] = []

    # --- Read-only properties (INV-HL-001: identifier immutable) ---

    @property
    def identifier(self) -> HypothesisIdentifier:
        return self._identifier

    @property
    def symbol(self) -> str:
        return self._symbol

    @property
    def instrument_type(self) -> InstrumentType:
        return self._instrument_type

    @property
    def status(self) -> HypothesisStatus:
        return self._status

    @property
    def title(self) -> str:
        return self._title

    @property
    def source_evidence(self) -> list[str]:
        return list(self._source_evidence)

    @property
    def skill_version(self) -> str:
        return self._skill_version

    @property
    def instruction_profile_version(self) -> str:
        return self._instruction_profile_version

    @property
    def updated_at(self) -> datetime.datetime:
        return self._updated_at

    @property
    def insider_risk(self) -> InsiderRisk | None:
        return self._insider_risk

    @property
    def requires_compliance_review(self) -> bool | None:
        return self._requires_compliance_review

    @property
    def mnpi_self_declared(self) -> bool | None:
        return self._mnpi_self_declared

    @property
    def auto_promotion_eligible(self) -> bool | None:
        return self._auto_promotion_eligible

    @property
    def promotion_mode(self) -> PromotionMode | None:
        return self._promotion_mode

    @property
    def latest_failure_summary(self) -> FailureSummary | None:
        return self._latest_failure_summary

    @property
    def performance_metrics(self) -> PerformanceMetrics | None:
        return self._performance_metrics

    @property
    def demo_window(self) -> DemoWindow | None:
        return self._demo_window

    @property
    def domain_events(self) -> list[DomainEvent]:
        return list(self._domain_events)

    def clear_domain_events(self) -> None:
        self._domain_events.clear()

    # --- Command methods ---

    def apply_backtest_result(
        self,
        passed: bool,
        performance_metrics: PerformanceMetrics,
        validation_run_identifier: ValidationRunIdentifier,
        trace: str,
        occurred_at: datetime.datetime,
    ) -> ReasonCode | None:
        """Apply the result of a backtest validation run.

        RULE-HL-001: backtest pass=false -> rejected (never reaches demo).
        Draft -> backtested (pass=true) or draft -> rejected (pass=false).

        Returns:
            None on successful transition.
            ReasonCode.STATE_CONFLICT if already in terminal or non-draft state.
            ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT if already in backtested state.
        """
        if self._status == HypothesisStatus.BACKTESTED and passed:
            return ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT

        if self._status == HypothesisStatus.REJECTED and not passed:
            return ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT

        if self._status != HypothesisStatus.DRAFT:
            return ReasonCode.STATE_CONFLICT

        self._performance_metrics = performance_metrics
        now = occurred_at

        if passed:
            self._status = HypothesisStatus.BACKTESTED
            self._updated_at = now
            self._domain_events.append(
                HypothesisBacktested(
                    identifier=self._identifier,
                    passed=True,
                    cost_adjusted_return=performance_metrics.cost_adjusted_return,
                    dsr=performance_metrics.dsr,
                    pbo=performance_metrics.pbo,
                    trace=trace,
                    occurred_at=now,
                )
            )
        else:
            self._status = HypothesisStatus.REJECTED
            self._updated_at = now
            self._domain_events.append(
                HypothesisBacktested(
                    identifier=self._identifier,
                    passed=False,
                    cost_adjusted_return=performance_metrics.cost_adjusted_return,
                    dsr=performance_metrics.dsr,
                    pbo=performance_metrics.pbo,
                    trace=trace,
                    occurred_at=now,
                )
            )
            self._domain_events.append(
                HypothesisRejected(
                    identifier=self._identifier,
                    decision=PromotionDecisionType.REJECTED,
                    action_reason_code=ReasonCode.REQUEST_VALIDATION_FAILED.value,
                    promotion_mode=PromotionMode.AUTO,
                    mnpi_self_declared=self._mnpi_self_declared or False,
                    insider_risk=self._insider_risk or InsiderRisk.HIGH,
                    trace=trace,
                    occurred_at=now,
                )
            )

        return None

    def apply_demo_result(
        self,
        demo_window: DemoWindow,
        promotable: bool,
        validation_run_identifier: ValidationRunIdentifier,
        partner_restricted_symbols: list[str],
        trace: str,
        occurred_at: datetime.datetime,
    ) -> ReasonCode | None:
        """Apply the result of a demo validation run.

        RULE-HL-002: auto-promote requires promotable=true, demoPeriodDays>=30,
                     requiresComplianceReview=false.
        RULE-HL-003: additionally requires instrumentType=ETF, insiderRisk=low,
                     mnpiSelfDeclared=true, symbol not in partnerRestrictedSymbols.
        RULE-HL-004: STOCK type never auto-promotes.

        Returns:
            None on successful processing.
            ReasonCode.STATE_CONFLICT if not in demo status.
            ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT if already live.
        """
        if self._status == HypothesisStatus.LIVE:
            return ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT

        if self._status != HypothesisStatus.DEMO:
            return ReasonCode.STATE_CONFLICT

        self._demo_window = demo_window
        now = occurred_at

        if not promotable:
            # demo completed but not promotable -> rejected
            self._status = HypothesisStatus.REJECTED
            self._updated_at = now
            self._domain_events.append(
                HypothesisRejected(
                    identifier=self._identifier,
                    decision=PromotionDecisionType.REJECTED,
                    action_reason_code=ReasonCode.REQUEST_VALIDATION_FAILED.value,
                    promotion_mode=PromotionMode.AUTO,
                    mnpi_self_declared=self._mnpi_self_declared or False,
                    insider_risk=self._insider_risk or InsiderRisk.HIGH,
                    trace=trace,
                    occurred_at=now,
                )
            )
            return None

        # Check auto-promotion eligibility (RULE-HL-002 + RULE-HL-003)
        can_auto_promote = self._check_auto_promotion_eligibility(
            demo_window=demo_window,
            partner_restricted_symbols=partner_restricted_symbols,
        )

        if can_auto_promote:
            self._status = HypothesisStatus.LIVE
            self._promotion_mode = PromotionMode.AUTO
            self._auto_promotion_eligible = True
            self._updated_at = now
            self._domain_events.append(
                HypothesisPromoted(
                    identifier=self._identifier,
                    decision=PromotionDecisionType.PROMOTED,
                    action_reason_code=ReasonCode.REQUEST_VALIDATION_FAILED.value,
                    promotion_mode=PromotionMode.AUTO,
                    mnpi_self_declared=self._mnpi_self_declared or False,
                    insider_risk=self._insider_risk or InsiderRisk.LOW,
                    trace=trace,
                    occurred_at=now,
                )
            )
        else:
            # Conditions not met -> stays in demo, waiting for manual promotion
            self._auto_promotion_eligible = False
            self._updated_at = now

        return None

    def promote(
        self,
        promotion_decision: PromotionDecision,
        trace: str,
        occurred_at: datetime.datetime,
    ) -> ReasonCode | None:
        """Manually promote hypothesis to live.

        INV-HL-002: only allowed from demo status.
        Accepts STOCK and ETF (manual promotion always allowed from demo).

        Returns:
            None on success.
            ReasonCode.STATE_CONFLICT if not in demo status.
            ReasonCode.COMPLIANCE_REVIEW_REQUIRED if compliance review is required.
            ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT if already live.
        """
        if self._status == HypothesisStatus.LIVE:
            return ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT

        if self._status != HypothesisStatus.DEMO:
            return ReasonCode.STATE_CONFLICT

        if self._requires_compliance_review:
            return ReasonCode.COMPLIANCE_REVIEW_REQUIRED

        now = occurred_at
        self._status = HypothesisStatus.LIVE
        self._promotion_mode = promotion_decision.promotion_mode
        self._updated_at = now

        self._domain_events.append(
            HypothesisPromoted(
                identifier=self._identifier,
                decision=promotion_decision.decision,
                action_reason_code=promotion_decision.action_reason_code.value,
                promotion_mode=promotion_decision.promotion_mode,
                mnpi_self_declared=self._mnpi_self_declared or False,
                insider_risk=self._insider_risk or InsiderRisk.HIGH,
                trace=trace,
                occurred_at=now,
            )
        )
        return None

    def reject(
        self,
        promotion_decision: PromotionDecision,
        trace: str,
        occurred_at: datetime.datetime,
    ) -> ReasonCode | None:
        """Manually reject hypothesis.

        Only allowed from demo status.

        Returns:
            None on success.
            ReasonCode.STATE_CONFLICT if not in demo status.
            ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT if already rejected.
        """
        if self._status == HypothesisStatus.REJECTED:
            return ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT

        if self._status != HypothesisStatus.DEMO:
            return ReasonCode.STATE_CONFLICT

        now = occurred_at
        self._status = HypothesisStatus.REJECTED
        self._updated_at = now

        self._domain_events.append(
            HypothesisRejected(
                identifier=self._identifier,
                decision=promotion_decision.decision,
                action_reason_code=promotion_decision.action_reason_code.value,
                promotion_mode=promotion_decision.promotion_mode,
                mnpi_self_declared=self._mnpi_self_declared or False,
                insider_risk=self._insider_risk or InsiderRisk.HIGH,
                trace=trace,
                occurred_at=now,
            )
        )
        return None

    def update_mnpi_self_declaration(
        self,
        value: bool,
        occurred_at: datetime.datetime,
    ) -> ReasonCode | None:
        """Update MNPI self-declaration.

        RULE-HL-008: only allowed when status=demo.

        Returns:
            None on success.
            ReasonCode.OPERATION_NOT_ALLOWED if status is not demo.
        """
        if self._status != HypothesisStatus.DEMO:
            return ReasonCode.OPERATION_NOT_ALLOWED

        self._mnpi_self_declared = value
        self._updated_at = occurred_at
        return None

    # --- Private helpers ---

    def _check_auto_promotion_eligibility(
        self,
        demo_window: DemoWindow,
        partner_restricted_symbols: list[str],
    ) -> bool:
        """Check all 7 auto-promotion conditions (RULE-HL-002 + RULE-HL-003).

        Conditions:
        1. promotable=true (caller guarantees this when calling this helper)
        2. demoPeriodDays >= 30
        3. requiresComplianceReview=false
        4. instrumentType=ETF
        5. insiderRisk=low
        6. mnpiSelfDeclared=true
        7. symbol not in partnerRestrictedSymbols
        """
        if demo_window.demo_period_days < 30:
            return False
        if self._requires_compliance_review:
            return False
        if self._instrument_type != InstrumentType.ETF:
            return False
        if self._insider_risk != InsiderRisk.LOW:
            return False
        if not self._mnpi_self_declared:
            return False
        return self._symbol not in partner_restricted_symbols


class InvalidStateTransitionError(Exception):
    """Raised when an invalid state transition is attempted on an aggregate."""


class InvariantViolationError(Exception):
    """Raised when a domain invariant is violated."""
