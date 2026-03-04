"""EventType enumeration for signal-generator domain."""

from enum import Enum


class EventType(str, Enum):
    """イベント種別。境界内ドメインイベントと境界外統合イベントを含む。"""

    # 境界内ドメインイベント
    SIGNAL_GENERATION_STARTED = "signal.generation.started"
    SIGNAL_GENERATION_COMPLETED = "signal.generation.completed"
    SIGNAL_GENERATION_FAILED = "signal.generation.failed"

    # 境界外統合イベント（AsyncAPI契約）
    SIGNAL_GENERATED = "signal.generated"
