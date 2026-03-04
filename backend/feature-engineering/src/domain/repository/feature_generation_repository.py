"""Repository ABC for FeatureGeneration aggregate."""

from __future__ import annotations

import datetime
from abc import ABC, abstractmethod
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from domain.model.feature_generation import FeatureGeneration
    from domain.value_object.enums import FeatureGenerationStatus


class FeatureGenerationRepository(ABC):
    """Abstract interface for persisting and retrieving FeatureGeneration aggregates."""

    @abstractmethod
    def find(self, identifier: str) -> FeatureGeneration | None:
        ...

    @abstractmethod
    def find_by_status(self, status: FeatureGenerationStatus) -> list[FeatureGeneration]:
        ...

    @abstractmethod
    def search(self, target_date: datetime.date | None = None) -> list[FeatureGeneration]:
        ...

    @abstractmethod
    def persist(self, feature_generation: FeatureGeneration) -> None:
        ...

    @abstractmethod
    def terminate(self, identifier: str) -> None:
        ...
