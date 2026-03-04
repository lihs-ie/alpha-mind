"""SignalGenerationFailedEvent domain event."""

import datetime
from dataclasses import dataclass

from signal_generator.domain.enums.event_type import EventType
from signal_generator.domain.enums.reason_code import ReasonCode


@dataclass(frozen=True)
class SignalGenerationFailedEvent:
    """signal.generation.failed: 失敗確定時に発行する境界内ドメインイベント。

    RULE-SG-008: reasonCode は必須。
    """

    identifier: str
    reason_code: ReasonCode
    trace: str
    occurred_at: datetime.datetime
    detail: str | None = None
    event_type: EventType = EventType.SIGNAL_GENERATION_FAILED

    def __post_init__(self) -> None:
        if self.event_type is not EventType.SIGNAL_GENERATION_FAILED:
            raise ValueError(f"event_type は SIGNAL_GENERATION_FAILED 固定 (got: {self.event_type.value})")
