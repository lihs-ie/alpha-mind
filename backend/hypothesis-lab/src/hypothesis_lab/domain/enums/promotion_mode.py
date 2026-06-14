"""PromotionMode enumeration."""

from enum import StrEnum


class PromotionMode(StrEnum):
    """最終昇格判断モード。"""

    MANUAL = "manual"
    AUTO = "auto"
