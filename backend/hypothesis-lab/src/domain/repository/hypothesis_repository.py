"""Repository ABC for Hypothesis aggregate."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from domain.model.hypothesis import Hypothesis
    from domain.value_object.enums import HypothesisStatus

HypothesisIdentifier = str


class HypothesisRepository(ABC):
    """Abstract interface for persisting and retrieving Hypothesis aggregates.

    Must-R-01: defines Find, FindByStatus, Search, Persist, Terminate.
    """

    @abstractmethod
    def find(self, identifier: HypothesisIdentifier) -> Hypothesis | None: ...

    @abstractmethod
    def find_by_status(self, status: HypothesisStatus) -> list[Hypothesis]: ...

    @abstractmethod
    def search(self, criteria: dict[str, Any] | None = None) -> list[Hypothesis]: ...

    @abstractmethod
    def persist(self, hypothesis: Hypothesis) -> None: ...

    @abstractmethod
    def terminate(self, identifier: HypothesisIdentifier) -> None: ...
