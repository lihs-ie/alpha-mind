"""HypothesisStatus enumeration."""

from enum import StrEnum


class HypothesisStatus(StrEnum):
    """仮説のライフサイクル状態。

    状態遷移:
      (none) -> DRAFT -> BACKTESTED -> DEMO -> LIVE (terminal)
                      \\-> REJECTED (terminal)
                                       \\-> REJECTED (terminal)
    """

    DRAFT = "draft"
    BACKTESTED = "backtested"
    DEMO = "demo"
    LIVE = "live"
    REJECTED = "rejected"

    def is_terminal(self) -> bool:
        """終端状態 (live or rejected) かどうかを判定する。"""
        return self in (HypothesisStatus.LIVE, HypothesisStatus.REJECTED)
