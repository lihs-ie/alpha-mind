"""Repository ABC for ValidationRun entity."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from domain.model.validation_run import ValidationRun
    from domain.value_object.enums import RunType

ValidationRunIdentifier = str


class ValidationRunRepository(ABC):
    """Abstract interface for persisting and retrieving ValidationRun entities.

    Must-R-02: defines Find, FindByRunType, Search, Persist, Terminate.
    """

    @abstractmethod
    def find(self, identifier: ValidationRunIdentifier) -> ValidationRun | None: ...

    @abstractmethod
    def find_by_run_type(self, run_type: RunType) -> list[ValidationRun]: ...

    @abstractmethod
    def search(self, criteria: dict[str, Any] | None = None) -> list[ValidationRun]: ...

    @abstractmethod
    def persist(self, validation_run: ValidationRun) -> None: ...

    @abstractmethod
    def terminate(self, identifier: ValidationRunIdentifier) -> None: ...
