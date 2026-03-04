"""Repository ABC for market data reference."""

from __future__ import annotations

import datetime
from abc import ABC, abstractmethod

from src.domain.value_object.market_snapshot import MarketSnapshot


class MarketDataRepository(ABC):
    """Abstract interface for reading market data (owned by data-collector, read-only here)."""

    @abstractmethod
    def find(self, identifier: str) -> MarketSnapshot | None:
        ...

    @abstractmethod
    def find_by_target_date(self, target_date: datetime.date) -> MarketSnapshot | None:
        ...
