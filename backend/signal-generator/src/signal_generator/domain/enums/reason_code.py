"""ReasonCode enumeration for signal-generator domain."""

from __future__ import annotations

from enum import StrEnum


class ReasonCode(StrEnum):
    """失敗理由コード。error-codes.json の signal-generator オーナー定義に準拠。"""

    MODEL_NOT_APPROVED = "MODEL_NOT_APPROVED"
    SIGNAL_GENERATION_FAILED = "SIGNAL_GENERATION_FAILED"
    REQUEST_VALIDATION_FAILED = "REQUEST_VALIDATION_FAILED"
    DEPENDENCY_TIMEOUT = "DEPENDENCY_TIMEOUT"
    DEPENDENCY_UNAVAILABLE = "DEPENDENCY_UNAVAILABLE"
    IDEMPOTENCY_DUPLICATE_EVENT = "IDEMPOTENCY_DUPLICATE_EVENT"
    STATE_CONFLICT = "STATE_CONFLICT"

    @classmethod
    def non_retryable(cls) -> frozenset[ReasonCode]:
        """再試行しない理由コードのセットを返す。"""
        return frozenset({cls.MODEL_NOT_APPROVED, cls.REQUEST_VALIDATION_FAILED})

    @classmethod
    def retryable(cls) -> frozenset[ReasonCode]:
        """再試行可能な理由コードのセットを返す。"""
        return frozenset({cls.DEPENDENCY_TIMEOUT, cls.DEPENDENCY_UNAVAILABLE})
