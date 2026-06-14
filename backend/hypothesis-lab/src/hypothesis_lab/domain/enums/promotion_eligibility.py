"""PromotionEligibility enumeration."""

from enum import StrEnum


class PromotionEligibility(StrEnum):
    """昇格適格性判定結果。"""

    ELIGIBLE_FOR_AUTO = "eligible_for_auto"
    ELIGIBLE_FOR_MANUAL = "eligible_for_manual"
    BLOCKED = "blocked"
