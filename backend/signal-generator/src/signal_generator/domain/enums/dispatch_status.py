"""DispatchStatus enumeration for signal-generator domain."""

from enum import StrEnum


class DispatchStatus(StrEnum):
    """シグナル発行処理の配信状態。pending -> published / failed の遷移を持つ。"""

    PENDING = "pending"
    PUBLISHED = "published"
    FAILED = "failed"

    def is_terminal(self) -> bool:
        """終端状態 (published or failed) かどうかを判定する。"""
        return self is not DispatchStatus.PENDING
