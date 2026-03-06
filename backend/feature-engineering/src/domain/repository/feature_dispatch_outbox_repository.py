"""Repository ABC for feature dispatch outbox entries."""

from __future__ import annotations

import datetime
from abc import ABC, abstractmethod

from domain.model.feature_dispatch_outbox import FeatureDispatchOutbox


class FeatureDispatchOutboxRepository(ABC):
    """Abstract interface for persisting and retrieving outbox entries."""

    @abstractmethod
    def find(self, identifier: str) -> FeatureDispatchOutbox | None: ...

    @abstractmethod
    def persist(self, outbox_entry: FeatureDispatchOutbox) -> None: ...

    @abstractmethod
    def mark_published(self, identifier: str, published_at: datetime.datetime) -> None: ...

    @abstractmethod
    def terminate(self, identifier: str) -> None: ...
