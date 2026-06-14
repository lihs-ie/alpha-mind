"""Domain events for the hypothesis-lab bounded context."""

from __future__ import annotations

import datetime
from dataclasses import dataclass

from domain.value_object.enums import InsiderRisk, PromotionDecisionType, PromotionMode

# Type alias for hypothesis aggregate identifier
HypothesisIdentifier = str


@dataclass(frozen=True)
class HypothesisBacktested:
    """Emitted when a backtest result is recorded on a Hypothesis.

    Must-DE-01: payload contains identifier, passed, cost_adjusted_return, dsr, pbo.
    Must-DE-04: envelope identifier is ULID.
    """

    identifier: HypothesisIdentifier
    passed: bool
    cost_adjusted_return: float
    dsr: float
    pbo: float
    trace: str
    occurred_at: datetime.datetime

    @property
    def event_type(self) -> str:
        return "hypothesis.backtested"


@dataclass(frozen=True)
class HypothesisPromoted:
    """Emitted when a Hypothesis transitions to live status.

    Must-DE-02: payload contains identifier, decision, action_reason_code,
    promotion_mode, mnpi_self_declared, insider_risk.
    Must-DE-04: envelope identifier is ULID.
    """

    identifier: HypothesisIdentifier
    decision: PromotionDecisionType
    action_reason_code: str
    promotion_mode: PromotionMode
    mnpi_self_declared: bool
    insider_risk: InsiderRisk
    trace: str
    occurred_at: datetime.datetime

    @property
    def event_type(self) -> str:
        return "hypothesis.promoted"


@dataclass(frozen=True)
class HypothesisRejected:
    """Emitted when a Hypothesis transitions to rejected status.

    Must-DE-03: payload contains identifier, decision, action_reason_code,
    promotion_mode, mnpi_self_declared, insider_risk.
    Must-DE-04: envelope identifier is ULID.
    """

    identifier: HypothesisIdentifier
    decision: PromotionDecisionType
    action_reason_code: str
    promotion_mode: PromotionMode
    mnpi_self_declared: bool
    insider_risk: InsiderRisk
    trace: str
    occurred_at: datetime.datetime

    @property
    def event_type(self) -> str:
        return "hypothesis.rejected"
