"""Feature dispatch outbox model."""

from __future__ import annotations

import datetime
import re
from dataclasses import dataclass
from enum import Enum

from domain.value_object.enums import PublishedEventType


class OutboxStatus(Enum):
    """Persistence status of a dispatch outbox entry."""

    PENDING = "pending"
    PUBLISHED = "published"


@dataclass(frozen=True)
class FeatureDispatchOutbox:
    """Durable outbox entry used to publish dispatch events after state persistence."""

    identifier: str
    trace: str
    published_event: PublishedEventType
    status: OutboxStatus
    created_at: datetime.datetime
    published_at: datetime.datetime | None = None

    def __post_init__(self) -> None:
        if not self.identifier:
            raise ValueError("identifier must not be empty")
        if not re.fullmatch(r"[0-9A-HJKMNP-TV-Z]{26}", self.identifier):
            raise ValueError(f"identifier must be a valid ULID (26 Crockford Base32 chars), got: {self.identifier}")
        if not self.trace:
            raise ValueError("trace must not be empty")
        if self.status == OutboxStatus.PUBLISHED and self.published_at is None:
            raise ValueError("published status requires published_at")

    def mark_published(self, published_at: datetime.datetime) -> "FeatureDispatchOutbox":
        """Return a published copy of the outbox entry."""
        return FeatureDispatchOutbox(
            identifier=self.identifier,
            trace=self.trace,
            published_event=self.published_event,
            status=OutboxStatus.PUBLISHED,
            created_at=self.created_at,
            published_at=published_at,
        )
