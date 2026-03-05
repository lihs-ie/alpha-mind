"""Domain events for the feature-engineering bounded context."""

from __future__ import annotations

import datetime
from dataclasses import dataclass

from domain.value_object.enums import ReasonCode


@dataclass(frozen=True)
class FeatureGenerationStarted:
    """Raised when feature generation processing begins."""

    identifier: str
    target_date: datetime.date
    trace: str
    occurred_at: datetime.datetime

    @property
    def event_type(self) -> str:
        return "feature.generation.started"


@dataclass(frozen=True)
class FeatureGenerationCompleted:
    """Raised when feature generation completes successfully."""

    identifier: str
    target_date: datetime.date
    feature_version: str
    storage_path: str
    trace: str
    occurred_at: datetime.datetime

    @property
    def event_type(self) -> str:
        return "feature.generation.completed"


@dataclass(frozen=True)
class FeatureGenerationFailed:
    """Raised when feature generation fails."""

    identifier: str
    reason_code: ReasonCode
    detail: str | None
    trace: str
    occurred_at: datetime.datetime

    @property
    def event_type(self) -> str:
        return "feature.generation.failed"
