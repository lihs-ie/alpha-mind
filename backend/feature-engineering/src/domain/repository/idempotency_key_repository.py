"""Repository ABC for idempotency key management."""

from __future__ import annotations

import datetime
from abc import ABC, abstractmethod


class IdempotencyKeyRepository(ABC):
    """Abstract interface for managing idempotency keys to prevent duplicate event processing."""

    @abstractmethod
    def find(self, identifier: str) -> datetime.datetime | None:
        """Return the processedAt timestamp if the identifier has been processed, else None."""
        ...

    @abstractmethod
    def persist(self, identifier: str, processed_at: datetime.datetime) -> None: ...

    @abstractmethod
    def terminate(self, identifier: str) -> None: ...
