"""PromotionDecision value object."""

from __future__ import annotations

from dataclasses import dataclass

from domain.value_object.enums import PromotionDecisionType, PromotionMode, ReasonCode


@dataclass(frozen=True)
class PromotionDecision:
    """Immutable value object representing the outcome of a promotion judgment.

    Attributes:
        decision: Whether the hypothesis was promoted or rejected.
        action_reason_code: Reason code explaining the decision.
        promotion_mode: Whether the decision was made manually or automatically.
    """

    decision: PromotionDecisionType
    action_reason_code: ReasonCode
    promotion_mode: PromotionMode
