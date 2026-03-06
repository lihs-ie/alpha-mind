"""Application service for feature generation orchestration."""

from __future__ import annotations

import datetime
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Protocol

from domain.event.domain_events import FeatureGenerationCompleted, FeatureGenerationFailed
from domain.factory.feature_dispatch_factory import FeatureDispatchFactory
from domain.factory.feature_generation_factory import FeatureGenerationFactory
from domain.model.feature_dispatch import FeatureDispatch
from domain.model.feature_dispatch_outbox import FeatureDispatchOutbox, OutboxStatus
from domain.model.feature_generation import FeatureGeneration
from domain.repository.feature_artifact_repository import FeatureArtifactRepository
from domain.repository.feature_dispatch_outbox_repository import FeatureDispatchOutboxRepository
from domain.repository.feature_dispatch_repository import FeatureDispatchRepository
from domain.repository.feature_generation_repository import FeatureGenerationRepository
from domain.repository.idempotency_key_repository import IdempotencyKeyRepository, ReservationStatus
from domain.repository.insight_record_repository import InsightRecordRepository
from domain.service.feature_leakage_policy import FeatureLeakagePolicy
from domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
from domain.value_object.enums import (
    DispatchStatus,
    FeatureGenerationStatus,
    PublishedEventType,
    ReasonCode,
    SourceStatusValue,
)
from domain.value_object.failure_detail import FailureDetail
from domain.value_object.feature_artifact import FeatureArtifact
from domain.value_object.insight_snapshot import InsightSnapshot
from domain.value_object.market_snapshot import MarketSnapshot
from domain.value_object.source_status import SourceStatus


class CompletedEventPublisher(Protocol):
    """Publishes a completed feature generation event."""

    def publish(self, event: FeatureGenerationCompleted) -> str | None:
        """Publish a completed event."""


class FailedEventPublisher(Protocol):
    """Publishes a failed feature generation event."""

    def publish(self, event: FeatureGenerationFailed) -> str | None:
        """Publish a failed event."""


class FeatureProcessingError(Exception):
    """Base exception for feature processing failures."""

    def __init__(
        self,
        *,
        status: int,
        title: str,
        detail: str,
        reason_code: ReasonCode,
        trace: str,
        retryable: bool,
    ) -> None:
        super().__init__(detail)
        self.status = status
        self.title = title
        self.detail = detail
        self.reason_code = reason_code
        self.trace = trace
        self.retryable = retryable


class RetryableProcessingError(FeatureProcessingError):
    """Raised when the request should be retried by Pub/Sub."""


class StateConflictError(FeatureProcessingError):
    """Raised when persisted state is internally inconsistent."""


@dataclass(frozen=True)
class EventEnvelope:
    """Normalized `market.collected` envelope."""

    identifier: str
    event_type: str
    occurred_at: datetime.datetime
    trace: str
    payload: Mapping[str, object]


@dataclass(frozen=True)
class NormalizedMarketPayload:
    """Normalized market payload plus validation issues detected in the use case."""

    market: MarketSnapshot
    validation_errors: tuple[str, ...]


class FeatureGenerationService:
    """Orchestrates feature generation from an incoming event to publish."""

    def __init__(
        self,
        *,
        feature_generation_repository: FeatureGenerationRepository,
        feature_dispatch_repository: FeatureDispatchRepository,
        feature_dispatch_outbox_repository: FeatureDispatchOutboxRepository,
        feature_artifact_repository: FeatureArtifactRepository,
        insight_record_repository: InsightRecordRepository,
        idempotency_key_repository: IdempotencyKeyRepository,
        features_generated_publisher: CompletedEventPublisher,
        features_generation_failed_publisher: FailedEventPublisher,
        feature_generation_factory: FeatureGenerationFactory,
        feature_dispatch_factory: FeatureDispatchFactory,
        point_in_time_join_policy: PointInTimeJoinPolicy,
        feature_leakage_policy: FeatureLeakagePolicy,
        feature_store_base_path: str,
        lease_seconds: int,
        clock: Callable[[], datetime.datetime],
    ) -> None:
        self._feature_generation_repository = feature_generation_repository
        self._feature_dispatch_repository = feature_dispatch_repository
        self._feature_dispatch_outbox_repository = feature_dispatch_outbox_repository
        self._feature_artifact_repository = feature_artifact_repository
        self._insight_record_repository = insight_record_repository
        self._idempotency_key_repository = idempotency_key_repository
        self._features_generated_publisher = features_generated_publisher
        self._features_generation_failed_publisher = features_generation_failed_publisher
        self._feature_generation_factory = feature_generation_factory
        self._feature_dispatch_factory = feature_dispatch_factory
        self._point_in_time_join_policy = point_in_time_join_policy
        self._feature_leakage_policy = feature_leakage_policy
        self._feature_store_base_path = feature_store_base_path.rstrip("/")
        self._lease_seconds = lease_seconds
        self._clock = clock

    def process(self, envelope: EventEnvelope) -> None:
        """Process a market event with idempotency, persistence, and publish ordering."""
        leased_at = self._clock()
        lease_expires_at = leased_at + datetime.timedelta(seconds=self._lease_seconds)
        reservation = self._idempotency_key_repository.reserve(
            envelope.identifier,
            leased_at,
            lease_expires_at,
            envelope.trace,
        )
        if reservation == ReservationStatus.PROCESSED:
            return
        if reservation == ReservationStatus.LEASED:
            raise RetryableProcessingError(
                status=503,
                title="Service Unavailable",
                detail="Event is already being processed by another worker.",
                reason_code=ReasonCode.STATE_CONFLICT,
                trace=envelope.trace,
                retryable=True,
            )

        try:
            self._process_reserved_event(envelope)
        except FeatureProcessingError:
            self._idempotency_key_repository.release(envelope.identifier, self._clock())
            raise
        except Exception as error:
            self._idempotency_key_repository.release(envelope.identifier, self._clock())
            raise RetryableProcessingError(
                status=500,
                title="Internal Server Error",
                detail="Feature generation failed unexpectedly.",
                reason_code=ReasonCode.FEATURE_GENERATION_FAILED,
                trace=envelope.trace,
                retryable=True,
            ) from error

    def _process_reserved_event(self, envelope: EventEnvelope) -> None:
        generation = self._feature_generation_repository.find(envelope.identifier)
        dispatch = self._feature_dispatch_repository.find(envelope.identifier)
        outbox_entry = self._feature_dispatch_outbox_repository.find(envelope.identifier)

        if generation is None and (dispatch is not None or outbox_entry is not None):
            raise StateConflictError(
                status=409,
                title="Conflict",
                detail="feature state exists without feature_generations.",
                reason_code=ReasonCode.STATE_CONFLICT,
                trace=envelope.trace,
                retryable=False,
            )

        if generation is None:
            generation = self._create_terminal_generation(envelope)
            self._feature_generation_repository.persist(generation)

        if dispatch is None:
            dispatch = self._feature_dispatch_factory.from_feature_generation(generation)
            self._feature_dispatch_repository.persist(dispatch)

        if outbox_entry is None:
            outbox_entry = FeatureDispatchOutbox(
                identifier=generation.identifier,
                trace=generation.trace,
                published_event=self._resolve_published_event(generation),
                status=OutboxStatus.PENDING,
                created_at=self._clock(),
            )
            self._feature_dispatch_outbox_repository.persist(outbox_entry)

        if dispatch.dispatch_status == DispatchStatus.PUBLISHED and outbox_entry.status == OutboxStatus.PENDING:
            self._feature_dispatch_outbox_repository.mark_published(
                envelope.identifier,
                dispatch.processed_at or self._clock(),
            )
            self._idempotency_key_repository.persist(envelope.identifier, self._clock(), envelope.trace)
            return

        if dispatch.dispatch_status == DispatchStatus.PENDING and outbox_entry.status == OutboxStatus.PUBLISHED:
            dispatch.publish(outbox_entry.published_event, outbox_entry.published_at or self._clock())
            self._feature_dispatch_repository.persist(dispatch)
            self._idempotency_key_repository.persist(envelope.identifier, self._clock(), envelope.trace)
            return

        if dispatch.dispatch_status == DispatchStatus.PUBLISHED and outbox_entry.status == OutboxStatus.PUBLISHED:
            self._idempotency_key_repository.persist(envelope.identifier, self._clock(), envelope.trace)
            return

        self._publish_and_finalize(generation, dispatch, outbox_entry)
        self._idempotency_key_repository.persist(envelope.identifier, self._clock(), envelope.trace)

    def _create_terminal_generation(self, envelope: EventEnvelope) -> FeatureGeneration:
        normalized_payload = self._normalize_market_payload(envelope)
        generation = self._feature_generation_factory.from_market_collected_event(
            identifier=envelope.identifier,
            market=normalized_payload.market,
            trace=envelope.trace,
        )

        if normalized_payload.validation_errors and generation.status == FeatureGenerationStatus.PENDING:
            generation.fail(
                failure_detail=self._build_request_validation_failure(normalized_payload.validation_errors),
                processed_at=self._clock(),
            )

        if generation.status != FeatureGenerationStatus.PENDING:
            return generation

        insight = self._load_insight_snapshot(generation.market.target_date)
        join_result = self._point_in_time_join_policy.evaluate(generation.market.target_date, insight)
        leakage_result = self._feature_leakage_policy.evaluate(generation.market.target_date, insight)
        if not join_result.approved or leakage_result.leakage_detected:
            generation.fail(
                failure_detail=FailureDetail(
                    reason_code=ReasonCode.DATA_QUALITY_LEAK_DETECTED,
                    detail=join_result.reason,
                    retryable=False,
                ),
                processed_at=self._clock(),
            )
            return generation

        feature_version = self._feature_generation_factory.generate_feature_version(generation.market.target_date)
        artifact = FeatureArtifact(
            feature_version=feature_version,
            storage_path=f"{self._feature_store_base_path}/{feature_version}.parquet",
            row_count=0,
            feature_count=0,
        )
        self._feature_artifact_repository.persist(artifact)
        generation.complete(
            feature_artifact=artifact,
            insight=insight,
            processed_at=self._clock(),
        )
        return generation

    def _load_insight_snapshot(self, target_date: datetime.date) -> InsightSnapshot:
        snapshot = self._insight_record_repository.find_by_target_date(target_date)
        if snapshot is not None:
            return snapshot
        return InsightSnapshot(
            record_count=0,
            latest_collected_at=None,
            filtered_by_target_date=True,
        )

    def _normalize_market_payload(self, envelope: EventEnvelope) -> NormalizedMarketPayload:
        payload = envelope.payload
        validation_errors: list[str] = []

        target_date = envelope.occurred_at.date()
        target_date_value = payload.get("targetDate")
        if isinstance(target_date_value, str) and target_date_value:
            try:
                target_date = datetime.date.fromisoformat(target_date_value)
            except ValueError:
                validation_errors.append("payload.targetDate")
        else:
            validation_errors.append("payload.targetDate")

        storage_path = ""
        storage_path_value = payload.get("storagePath")
        if isinstance(storage_path_value, str):
            storage_path = storage_path_value
            if not storage_path:
                validation_errors.append("payload.storagePath")
        else:
            validation_errors.append("payload.storagePath")

        source_status = SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK)
        source_status_value = payload.get("sourceStatus")
        if isinstance(source_status_value, dict):
            source_status = self._normalize_source_status(source_status_value, validation_errors)
        else:
            validation_errors.append("payload.sourceStatus")

        return NormalizedMarketPayload(
            market=MarketSnapshot(
                target_date=target_date,
                storage_path=storage_path,
                source_status=source_status,
            ),
            validation_errors=tuple(validation_errors),
        )

    def _normalize_source_status(
        self,
        value: Mapping[str, object],
        validation_errors: list[str],
    ) -> SourceStatus:
        jp = self._parse_source_status_value(value.get("jp"), "payload.sourceStatus.jp", validation_errors)
        us = self._parse_source_status_value(value.get("us"), "payload.sourceStatus.us", validation_errors)
        return SourceStatus(jp=jp, us=us)

    def _parse_source_status_value(
        self,
        value: object,
        field_name: str,
        validation_errors: list[str],
    ) -> SourceStatusValue:
        if not isinstance(value, str):
            validation_errors.append(field_name)
            return SourceStatusValue.OK
        try:
            return SourceStatusValue(value)
        except ValueError:
            validation_errors.append(field_name)
            return SourceStatusValue.OK

    def _build_request_validation_failure(self, fields: tuple[str, ...]) -> FailureDetail:
        field_list = ", ".join(fields)
        return FailureDetail(
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            detail=f"Required payload fields are invalid: {field_list}",
            retryable=False,
        )

    def _resolve_published_event(self, generation: FeatureGeneration) -> PublishedEventType:
        if generation.status == FeatureGenerationStatus.GENERATED:
            return PublishedEventType.FEATURES_GENERATED
        return PublishedEventType.FEATURES_GENERATION_FAILED

    def _publish_and_finalize(
        self,
        generation: FeatureGeneration,
        dispatch: FeatureDispatch,
        outbox_entry: FeatureDispatchOutbox,
    ) -> None:
        processed_at = self._clock()
        if outbox_entry.published_event == PublishedEventType.FEATURES_GENERATED:
            completed_event = self._build_completed_event(generation)
            self._features_generated_publisher.publish(completed_event)
            dispatch.publish(PublishedEventType.FEATURES_GENERATED, processed_at)
        else:
            failed_event = self._build_failed_event(generation)
            self._features_generation_failed_publisher.publish(failed_event)
            dispatch.publish(PublishedEventType.FEATURES_GENERATION_FAILED, processed_at)
        self._feature_dispatch_repository.persist(dispatch)
        self._feature_dispatch_outbox_repository.mark_published(generation.identifier, processed_at)

    def _build_completed_event(self, generation: FeatureGeneration) -> FeatureGenerationCompleted:
        if generation.feature_artifact is None or generation.processed_at is None:
            raise StateConflictError(
                status=409,
                title="Conflict",
                detail="Generated feature_generation is missing artifact or processedAt.",
                reason_code=ReasonCode.STATE_CONFLICT,
                trace=generation.trace,
                retryable=False,
            )
        return FeatureGenerationCompleted(
            identifier=generation.identifier,
            target_date=generation.market.target_date,
            feature_version=generation.feature_artifact.feature_version,
            storage_path=generation.feature_artifact.storage_path,
            trace=generation.trace,
            occurred_at=generation.processed_at,
        )

    def _build_failed_event(self, generation: FeatureGeneration) -> FeatureGenerationFailed:
        if generation.failure_detail is None or generation.processed_at is None:
            raise StateConflictError(
                status=409,
                title="Conflict",
                detail="Failed feature_generation is missing failureDetail or processedAt.",
                reason_code=ReasonCode.STATE_CONFLICT,
                trace=generation.trace,
                retryable=False,
            )
        return FeatureGenerationFailed(
            identifier=generation.identifier,
            reason_code=generation.failure_detail.reason_code,
            detail=generation.failure_detail.detail,
            trace=generation.trace,
            occurred_at=generation.processed_at,
        )
