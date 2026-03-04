"""ModelStatus enumeration for signal-generator domain."""

from enum import StrEnum


class ModelStatus(StrEnum):
    """モデル状態。RULE-SG-002: approved のみ推論に利用できる。"""

    CANDIDATE = "candidate"
    APPROVED = "approved"
    REJECTED = "rejected"

    def is_usable_for_inference(self) -> bool:
        """RULE-SG-002: approved モデルのみ推論に利用可能。candidate/rejected は利用禁止。"""
        return self is ModelStatus.APPROVED
