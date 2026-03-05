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
    def reserve(self, identifier: str, trace: str) -> bool:
        """Atomically reserve an identifier for processing.

        Returns True if newly reserved (caller should proceed with processing).
        Returns False if already reserved or fully processed (duplicate).

        Implementations must use atomic operations (e.g., Firestore ``create``)
        to prevent concurrent duplicate processing under RULE-FE-004.
        """
        ...

    @abstractmethod
    def persist(self, identifier: str, processed_at: datetime.datetime, trace: str) -> None: ...

    @abstractmethod
    def terminate(self, identifier: str) -> None: ...
