"""DispatchDecision value object - result of a dispatch operation."""

from __future__ import annotations

from dataclasses import dataclass

from domain.value_object.enums import DispatchStatus, PublishedEventType, ReasonCode


@dataclass(frozen=True)
class DispatchDecision:
    """Result of a dispatch decision including status, event type, and optional reason code."""

    dispatch_status: DispatchStatus
    published_event: PublishedEventType | None
    reason_code: ReasonCode | None

    def __post_init__(self) -> None:
        if self.dispatch_status == DispatchStatus.FAILED and self.published_event is not None:
            raise ValueError("failed dispatch decision must not have published_event")
        if self.dispatch_status == DispatchStatus.PUBLISHED and self.reason_code is not None:
            raise ValueError("published dispatch decision must not have reason_code")
