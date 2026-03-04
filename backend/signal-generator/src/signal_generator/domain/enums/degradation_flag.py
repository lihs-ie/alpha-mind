"""DegradationFlag enumeration for signal-generator domain."""

from enum import StrEnum


class DegradationFlag(StrEnum):
    """モデル劣化フラグ。RULE-SG-007: block は必ずコンプライアンスレビューを要求する。"""

    NORMAL = "normal"
    WARN = "warn"
    BLOCK = "block"

    def requires_compliance_review(self) -> bool:
        """RULE-SG-007: block フラグ時はコンプライアンスレビューが必須。"""
        return self is DegradationFlag.BLOCK
