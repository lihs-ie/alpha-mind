"""PromotionDecision value object."""

from dataclasses import dataclass

from hypothesis_lab.domain.enums.decision_result import DecisionResult
from hypothesis_lab.domain.enums.operator_action_reason_code import OperatorActionReasonCode
from hypothesis_lab.domain.enums.promotion_mode import PromotionMode


@dataclass(frozen=True)
class PromotionDecision:
    """昇格判断の記録。

    INV: 全フィールド必須。Value Object として値比較で等価判定し、immutable。
    """

    decision: DecisionResult
    action_reason_code: OperatorActionReasonCode
    promotion_mode: PromotionMode
