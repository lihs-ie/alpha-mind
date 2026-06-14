"""Repository ABC for FailureSummary (failure knowledge)."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from domain.value_object.enums import ReasonCode
    from domain.value_object.failure_summary import FailureSummary

FailureKnowledgeIdentifier = str


class FailureKnowledgeRepository(ABC):
    """Abstract interface for persisting and retrieving FailureSummary records.

    Must-R-03: defines Find, FindByReasonCode, Search, Persist, Terminate.
    """

    @abstractmethod
    def find(self, identifier: FailureKnowledgeIdentifier) -> FailureSummary | None: ...

    @abstractmethod
    def find_by_reason_code(self, reason_code: ReasonCode) -> list[FailureSummary]: ...

    @abstractmethod
    def search(self, criteria: dict[str, Any] | None = None) -> list[FailureSummary]: ...

    @abstractmethod
    def persist(self, failure_summary: FailureSummary) -> None: ...

    @abstractmethod
    def terminate(self, identifier: FailureKnowledgeIdentifier) -> None: ...
