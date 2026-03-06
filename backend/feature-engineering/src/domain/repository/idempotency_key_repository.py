"""Repository ABC for idempotency key management."""

from __future__ import annotations

import datetime
from abc import ABC, abstractmethod
from enum import Enum


class ReservationStatus(Enum):
    """Result of trying to reserve an idempotency key for processing."""

    ACQUIRED = "acquired"
    PROCESSED = "processed"
    LEASED = "leased"


class IdempotencyKeyRepository(ABC):
    """Abstract interface for managing idempotency keys to prevent duplicate event processing."""

    @abstractmethod
    def find(self, identifier: str) -> datetime.datetime | None:
        """Return the processedAt timestamp if the identifier has been processed, else None."""
        ...

    @abstractmethod
    def reserve(
        self,
        identifier: str,
        leased_at: datetime.datetime,
        lease_expires_at: datetime.datetime,
        trace: str,
    ) -> ReservationStatus:
        """Reserve the identifier for processing using a short-lived lease."""
        ...

    @abstractmethod
    def persist(self, identifier: str, processed_at: datetime.datetime, trace: str) -> None: ...

    @abstractmethod
    def release(self, identifier: str, released_at: datetime.datetime) -> None:
        """Release an in-flight lease so the event can be retried."""
        ...

    @abstractmethod
    def terminate(self, identifier: str) -> None: ...
