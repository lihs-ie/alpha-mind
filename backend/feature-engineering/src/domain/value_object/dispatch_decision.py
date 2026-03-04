"""DispatchDecision value object - result of a dispatch operation."""

from dataclasses import dataclass

from domain.value_object.enums import DispatchStatus, PublishedEventType, ReasonCode


@dataclass(frozen=True)
class DispatchDecision:
    """Result of a dispatch decision including status, event type, and optional reason code."""

    dispatch_status: DispatchStatus
    published_event: PublishedEventType | None
    reason_code: ReasonCode | None
