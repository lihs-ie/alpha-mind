"""Port (ABC) for writing feature generation audit records."""

import datetime
from abc import ABC, abstractmethod

from domain.value_object.enums import ReasonCode


class FeatureAuditWriter(ABC):
    """Abstract interface for recording audit trail entries for feature generation."""

    @abstractmethod
    def write_success(
        self,
        identifier: str,
        trace: str,
        target_date: datetime.date,
        feature_version: str,
    ) -> None:
        """Record a successful feature generation audit entry."""
        ...

    @abstractmethod
    def write_failure(
        self,
        identifier: str,
        trace: str,
        reason_code: ReasonCode,
        detail: str | None,
    ) -> None:
        """Record a failed feature generation audit entry."""
        ...

    @abstractmethod
    def write_duplicate(self, identifier: str, trace: str) -> None:
        """Record a duplicate (idempotent skip) audit entry."""
        ...
