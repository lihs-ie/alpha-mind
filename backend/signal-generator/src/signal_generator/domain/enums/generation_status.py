"""GenerationStatus enumeration for signal-generator domain."""

from enum import Enum


class GenerationStatus(str, Enum):
    """シグナル生成処理の状態。pending -> generated / failed の遷移を持つ。"""

    PENDING = "pending"
    GENERATED = "generated"
    FAILED = "failed"

    def is_terminal(self) -> bool:
        """終端状態（generated または failed）かどうかを判定する。"""
        return self is not GenerationStatus.PENDING
