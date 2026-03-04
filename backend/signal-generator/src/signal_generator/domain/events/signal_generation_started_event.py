"""SignalGenerationStartedEvent domain event."""

import datetime
from dataclasses import dataclass

from signal_generator.domain.enums.event_type import EventType


@dataclass(frozen=True)
class SignalGenerationStartedEvent:
    """signal.generation.started: 受信処理開始時に発行する境界内ドメインイベント。"""

    identifier: str
    feature_version: str
    trace: str
    occurred_at: datetime.datetime
    event_type: EventType = EventType.SIGNAL_GENERATION_STARTED
