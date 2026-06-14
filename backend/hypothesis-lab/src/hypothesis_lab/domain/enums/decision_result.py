"""DecisionResult enumeration."""

from enum import StrEnum


class DecisionResult(StrEnum):
    """昇格判定結果。"""

    PROMOTED = "promoted"
    REJECTED = "rejected"
