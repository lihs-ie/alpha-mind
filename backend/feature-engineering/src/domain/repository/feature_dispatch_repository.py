"""Repository ABC for FeatureDispatch aggregate."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from src.domain.model.feature_dispatch import FeatureDispatch


class FeatureDispatchRepository(ABC):
    """Abstract interface for persisting and retrieving FeatureDispatch aggregates."""

    @abstractmethod
    def find(self, identifier: str) -> FeatureDispatch | None:
        ...

    @abstractmethod
    def persist(self, feature_dispatch: FeatureDispatch) -> None:
        ...

    @abstractmethod
    def terminate(self, identifier: str) -> None:
        ...
