"""Repository ABC for insight record reference."""

from __future__ import annotations

import datetime
from abc import ABC, abstractmethod

from src.domain.value_object.insight_snapshot import InsightSnapshot


class InsightRecordRepository(ABC):
    """Abstract interface for reading insight records (owned by insight-collector, read-only here)."""

    @abstractmethod
    def search(self, target_date: datetime.date | None = None) -> list[InsightSnapshot]:
        ...

    @abstractmethod
    def find_by_target_date(self, target_date: datetime.date) -> InsightSnapshot | None:
        ...
