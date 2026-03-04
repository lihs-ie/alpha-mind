"""DispatchStatus enumeration for signal-generator domain."""

from enum import Enum


class DispatchStatus(str, Enum):
    """シグナル発行処理の配信状態。pending -> published / failed の遷移を持つ。"""

    PENDING = "pending"
    PUBLISHED = "published"
    FAILED = "failed"

    def is_terminal(self) -> bool:
        """終端状態（published または failed）かどうかを判定する。"""
        return self is not DispatchStatus.PENDING
