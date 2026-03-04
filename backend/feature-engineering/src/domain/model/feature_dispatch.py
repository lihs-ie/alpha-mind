"""FeatureDispatch aggregate root."""

from __future__ import annotations

import datetime

from domain.value_object.enums import DispatchStatus, PublishedEventType, ReasonCode


class FeatureDispatch:
    """Aggregate root for feature dispatch lifecycle.

    Enforces invariants:
    - INV-FE-004: same event identifier can only transition to published once
    """

    def __init__(
        self,
        identifier: str,
        dispatch_status: DispatchStatus,
        trace: str,
        published_event: PublishedEventType | None = None,
        reason_code: ReasonCode | None = None,
        processed_at: datetime.datetime | None = None,
    ) -> None:
        if not identifier:
            raise ValueError("identifier must not be empty")
        if not trace:
            raise ValueError("trace must not be empty")

        # Invariant: failed status requires reason_code
        if dispatch_status == DispatchStatus.FAILED and reason_code is None:
            raise ValueError("failed dispatch status requires reason_code")

        # Invariant: published status requires published_event
        if dispatch_status == DispatchStatus.PUBLISHED and published_event is None:
            raise ValueError("published dispatch status requires published_event")

        self._identifier = identifier
        self._dispatch_status = dispatch_status
        self._trace = trace
        self._published_event = published_event
        self._reason_code = reason_code
        self._processed_at = processed_at

    @property
    def identifier(self) -> str:
        return self._identifier

    @property
    def dispatch_status(self) -> DispatchStatus:
        return self._dispatch_status

    @property
    def trace(self) -> str:
        return self._trace

    @property
    def published_event(self) -> PublishedEventType | None:
        return self._published_event

    @property
    def reason_code(self) -> ReasonCode | None:
        return self._reason_code

    @property
    def processed_at(self) -> datetime.datetime | None:
        return self._processed_at

    def publish(
        self,
        published_event: PublishedEventType,
        processed_at: datetime.datetime,
    ) -> None:
        """Transition to published state. Enforces INV-FE-004."""
        if self._dispatch_status != DispatchStatus.PENDING:
            raise InvalidDispatchTransitionError(
                f"Cannot publish from status {self._dispatch_status.value}, must be pending"
            )

        self._published_event = published_event
        self._dispatch_status = DispatchStatus.PUBLISHED
        self._processed_at = processed_at

    def fail(
        self,
        reason_code: ReasonCode,
        processed_at: datetime.datetime,
    ) -> None:
        """Transition to failed state."""
        if self._dispatch_status != DispatchStatus.PENDING:
            raise InvalidDispatchTransitionError(
                f"Cannot fail from status {self._dispatch_status.value}, must be pending"
            )

        self._reason_code = reason_code
        self._dispatch_status = DispatchStatus.FAILED
        self._processed_at = processed_at


class InvalidDispatchTransitionError(Exception):
    """Raised when an invalid state transition is attempted on a dispatch aggregate."""
