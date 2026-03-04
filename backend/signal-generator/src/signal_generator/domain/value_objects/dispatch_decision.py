"""DispatchDecision value object."""

from dataclasses import dataclass

from signal_generator.domain.enums.dispatch_status import DispatchStatus
from signal_generator.domain.enums.event_type import EventType
from signal_generator.domain.enums.reason_code import ReasonCode


@dataclass(frozen=True)
class DispatchDecision:
    """1回のシグナル発行処理の配信結果と理由。"""

    dispatch_status: DispatchStatus
    published_event: EventType | None = None
    reason_code: ReasonCode | None = None
