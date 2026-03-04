"""FeatureGeneration aggregate root."""

from __future__ import annotations

import datetime

from domain.event.domain_events import (
    FeatureGenerationCompleted,
    FeatureGenerationFailed,
    FeatureGenerationStarted,
)
from domain.value_object.enums import FeatureGenerationStatus
from domain.value_object.failure_detail import FailureDetail
from domain.value_object.feature_artifact import FeatureArtifact
from domain.value_object.insight_snapshot import InsightSnapshot
from domain.value_object.market_snapshot import MarketSnapshot

DomainEvent = FeatureGenerationStarted | FeatureGenerationCompleted | FeatureGenerationFailed


class FeatureGeneration:
    """Aggregate root for feature generation lifecycle.

    Enforces invariants:
    - INV-FE-001: generated state requires feature_version, storage_path, row_count, feature_count
    - INV-FE-002: failed state requires reason_code
    - INV-FE-003: insight.latest_collected_at <= target_date
    - INV-FE-005: identifier and feature_version immutable after set
    """

    def __init__(
        self,
        identifier: str,
        status: FeatureGenerationStatus,
        market: MarketSnapshot,
        trace: str,
        insight: InsightSnapshot | None = None,
        feature_artifact: FeatureArtifact | None = None,
        failure_detail: FailureDetail | None = None,
        processed_at: datetime.datetime | None = None,
    ) -> None:
        if not identifier:
            raise ValueError("identifier must not be empty")
        if not trace:
            raise ValueError("trace must not be empty")

        # INV-FE-001: generated state requires artifact
        if status == FeatureGenerationStatus.GENERATED and feature_artifact is None:
            raise ValueError("INV-FE-001: generated status requires feature_artifact")

        # INV-FE-002: failed state requires failure_detail
        if status == FeatureGenerationStatus.FAILED and failure_detail is None:
            raise ValueError("INV-FE-002: failed status requires failure_detail")

        self._identifier = identifier
        self._status = status
        self._market = market
        self._trace = trace
        self._insight = insight
        self._feature_artifact = feature_artifact
        self._failure_detail = failure_detail
        self._processed_at = processed_at
        self._domain_events: list[DomainEvent] = []

    @property
    def identifier(self) -> str:
        return self._identifier

    @property
    def status(self) -> FeatureGenerationStatus:
        return self._status

    @property
    def market(self) -> MarketSnapshot:
        return self._market

    @property
    def trace(self) -> str:
        return self._trace

    @property
    def insight(self) -> InsightSnapshot | None:
        return self._insight

    @property
    def feature_artifact(self) -> FeatureArtifact | None:
        return self._feature_artifact

    @property
    def failure_detail(self) -> FailureDetail | None:
        return self._failure_detail

    @property
    def processed_at(self) -> datetime.datetime | None:
        return self._processed_at

    @property
    def domain_events(self) -> list[DomainEvent]:
        return list(self._domain_events)

    def record_domain_event(self, event: DomainEvent) -> None:
        """Append a domain event. Used by factories to register creation events."""
        self._domain_events.append(event)

    def clear_domain_events(self) -> None:
        self._domain_events.clear()

    def complete(
        self,
        feature_artifact: FeatureArtifact,
        insight: InsightSnapshot,
        processed_at: datetime.datetime,
    ) -> None:
        """Transition to generated state. Enforces INV-FE-001, INV-FE-005."""
        if self._status != FeatureGenerationStatus.PENDING:
            raise InvalidStateTransitionError(
                f"Cannot complete from status {self._status.value}, must be pending"
            )

        self._feature_artifact = feature_artifact
        self._insight = insight
        self._status = FeatureGenerationStatus.GENERATED
        self._processed_at = processed_at

        self._domain_events.append(
            FeatureGenerationCompleted(
                identifier=self._identifier,
                target_date=self._market.target_date,
                feature_version=feature_artifact.feature_version,
                storage_path=feature_artifact.storage_path,
                trace=self._trace,
                occurred_at=processed_at,
            )
        )

    def fail(
        self,
        failure_detail: FailureDetail,
        processed_at: datetime.datetime,
    ) -> None:
        """Transition to failed state. Enforces INV-FE-002."""
        if self._status != FeatureGenerationStatus.PENDING:
            raise InvalidStateTransitionError(
                f"Cannot fail from status {self._status.value}, must be pending"
            )

        self._failure_detail = failure_detail
        self._status = FeatureGenerationStatus.FAILED
        self._processed_at = processed_at

        self._domain_events.append(
            FeatureGenerationFailed(
                identifier=self._identifier,
                reason_code=failure_detail.reason_code,
                detail=failure_detail.detail,
                trace=self._trace,
                occurred_at=processed_at,
            )
        )


class InvalidStateTransitionError(Exception):
    """Raised when an invalid state transition is attempted on an aggregate."""
