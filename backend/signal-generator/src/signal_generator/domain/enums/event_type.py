"""EventType enumeration for signal-generator domain."""

from enum import StrEnum


class EventType(StrEnum):
    """イベント種別。境界内ドメインイベントと境界外統合イベントを含む。"""

    # 境界内ドメインイベント
    SIGNAL_GENERATION_STARTED = "signal.generation.started"
    SIGNAL_GENERATION_COMPLETED = "signal.generation.completed"
    SIGNAL_GENERATION_FAILED = "signal.generation.failed"

    # 境界外統合イベント (AsyncAPI contract)
    SIGNAL_GENERATED = "signal.generated"

    def is_integration_event(self) -> bool:
        """境界外統合イベント (AsyncAPI contract) かどうかを判定する。"""
        return self in _INTEGRATION_EVENT_TYPES


_INTEGRATION_EVENT_TYPES: frozenset[EventType] = frozenset(
    {EventType.SIGNAL_GENERATED, EventType.SIGNAL_GENERATION_FAILED}
)
