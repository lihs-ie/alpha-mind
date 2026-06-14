"""InsiderRisk enumeration."""

from enum import StrEnum


class InsiderRisk(StrEnum):
    """インサイダー接触リスク評価。"""

    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
