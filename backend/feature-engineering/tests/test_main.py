"""HTTP tests for the feature-engineering service."""

from __future__ import annotations

import base64
import datetime
import json
from dataclasses import dataclass

from flask import Flask

from application.feature_generation_service import FeatureGenerationService
from domain.event.domain_events import FeatureGenerationCompleted, FeatureGenerationFailed
from domain.factory.feature_dispatch_factory import FeatureDispatchFactory
from domain.factory.feature_generation_factory import FeatureGenerationFactory
from domain.model.feature_dispatch import FeatureDispatch
from domain.model.feature_dispatch_outbox import FeatureDispatchOutbox, OutboxStatus
from domain.model.feature_generation import FeatureGeneration
from domain.repository.idempotency_key_repository import ReservationStatus
from domain.service.feature_leakage_policy import FeatureLeakagePolicy
from domain.service.feature_version_generator import FeatureVersionGenerator
from domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
from domain.value_object.enums import DispatchStatus, FeatureGenerationStatus, PublishedEventType, ReasonCode
from domain.value_object.feature_artifact import FeatureArtifact
from domain.value_object.insight_snapshot import InsightSnapshot
from main import create_app

VALID_IDENTIFIER = "01ARZ3NDEKTSV4RRFFQ69G5FAA"
VALID_TRACE = "01ARZ3NDEKTSV4RRFFQ69G5FAA"


class StubFeatureVersionGenerator(FeatureVersionGenerator):
    """Deterministic generator for HTTP tests."""

    def generate(self, target_date: datetime.date) -> str:
        """Return a stable feature version."""
        return f"v{target_date.strftime('%Y%m%d')}-001"


@dataclass
class IdempotencyRecord:
    """In-memory idempotency state used by tests."""

    processed_at: datetime.datetime | None
    lease_expires_at: datetime.datetime | None
    trace: str


class InMemoryFeatureGenerationRepository:
    """In-memory feature generation repository for HTTP tests."""

    def __init__(self) -> None:
        self.items: dict[str, FeatureGeneration] = {}

    def find(self, identifier: str) -> FeatureGeneration | None:
        """Find a generation by identifier."""
        return self.items.get(identifier)

    def find_by_status(self, status: FeatureGenerationStatus) -> list[FeatureGeneration]:
        """Find generations by status."""
        return [item for item in self.items.values() if item.status == status]

    def search(self, target_date: datetime.date | None = None) -> list[FeatureGeneration]:
        """Search generations."""
        if target_date is None:
            return list(self.items.values())
        return [item for item in self.items.values() if item.market.target_date == target_date]

    def persist(self, feature_generation: FeatureGeneration) -> None:
        """Persist a generation."""
        self.items[feature_generation.identifier] = feature_generation

    def terminate(self, identifier: str) -> None:
        """Delete a generation."""
        self.items.pop(identifier, None)


class InMemoryFeatureDispatchRepository:
    """In-memory feature dispatch repository for HTTP tests."""

    def __init__(self) -> None:
        self.items: dict[str, FeatureDispatch] = {}

    def find(self, identifier: str) -> FeatureDispatch | None:
        """Find a dispatch by identifier."""
        return self.items.get(identifier)

    def persist(self, feature_dispatch: FeatureDispatch) -> None:
        """Persist a dispatch."""
        self.items[feature_dispatch.identifier] = feature_dispatch

    def terminate(self, identifier: str) -> None:
        """Delete a dispatch."""
        self.items.pop(identifier, None)


class InMemoryFeatureArtifactRepository:
    """In-memory feature artifact repository for HTTP tests."""

    def __init__(self) -> None:
        self.items: dict[str, FeatureArtifact] = {}
        self.persisted_versions: list[str] = []

    def persist(self, feature_artifact: FeatureArtifact) -> None:
        """Persist an artifact."""
        self.items[feature_artifact.feature_version] = feature_artifact
        self.persisted_versions.append(feature_artifact.feature_version)

    def find(self, feature_version: str) -> FeatureArtifact | None:
        """Find an artifact by feature version."""
        return self.items.get(feature_version)

    def terminate(self, feature_version: str) -> None:
        """Delete an artifact."""
        self.items.pop(feature_version, None)


class InMemoryInsightRecordRepository:
    """In-memory insight repository for HTTP tests."""

    def __init__(self, snapshot: InsightSnapshot | None = None) -> None:
        self.snapshot = snapshot

    def search(self, target_date: datetime.date | None = None) -> list[InsightSnapshot]:
        """Search snapshots."""
        if self.snapshot is None:
            return []
        return [self.snapshot]

    def find_by_target_date(self, target_date: datetime.date) -> InsightSnapshot | None:
        """Return a fixed snapshot."""
        return self.snapshot


class InMemoryIdempotencyKeyRepository:
    """In-memory lease-based idempotency repository for HTTP tests."""

    def __init__(self) -> None:
        self.items: dict[str, IdempotencyRecord] = {}

    def find(self, identifier: str) -> datetime.datetime | None:
        """Return processedAt for a completed event."""
        record = self.items.get(identifier)
        if record is None:
            return None
        return record.processed_at

    def reserve(
        self,
        identifier: str,
        leased_at: datetime.datetime,
        lease_expires_at: datetime.datetime,
        trace: str,
    ) -> ReservationStatus:
        """Acquire or inspect an in-memory lease."""
        record = self.items.get(identifier)
        if record is None:
            self.items[identifier] = IdempotencyRecord(None, lease_expires_at, trace)
            return ReservationStatus.ACQUIRED
        if record.processed_at is not None:
            return ReservationStatus.PROCESSED
        if record.lease_expires_at is not None and record.lease_expires_at > leased_at:
            return ReservationStatus.LEASED
        self.items[identifier] = IdempotencyRecord(None, lease_expires_at, trace)
        return ReservationStatus.ACQUIRED

    def persist(self, identifier: str, processed_at: datetime.datetime, trace: str) -> None:
        """Mark the event as processed."""
        self.items[identifier] = IdempotencyRecord(processed_at, None, trace)

    def release(self, identifier: str, released_at: datetime.datetime) -> None:
        """Release an active lease."""
        record = self.items.get(identifier)
        if record is None:
            return
        self.items[identifier] = IdempotencyRecord(record.processed_at, released_at, record.trace)

    def terminate(self, identifier: str) -> None:
        """Delete the idempotency record."""
        self.items.pop(identifier, None)


class InMemoryFeatureDispatchOutboxRepository:
    """In-memory outbox repository for HTTP tests."""

    def __init__(self) -> None:
        self.items: dict[str, FeatureDispatchOutbox] = {}

    def find(self, identifier: str) -> FeatureDispatchOutbox | None:
        """Find an outbox entry by identifier."""
        return self.items.get(identifier)

    def persist(self, outbox_entry: FeatureDispatchOutbox) -> None:
        """Persist an outbox entry."""
        self.items[outbox_entry.identifier] = outbox_entry

    def mark_published(self, identifier: str, published_at: datetime.datetime) -> None:
        """Mark an outbox entry as published."""
        entry = self.items.get(identifier)
        if entry is None:
            return
        self.items[identifier] = entry.mark_published(published_at)

    def terminate(self, identifier: str) -> None:
        """Delete an outbox entry."""
        self.items.pop(identifier, None)


class RecordingGeneratedPublisher:
    """Records published completed events."""

    def __init__(self) -> None:
        self.events: list[FeatureGenerationCompleted] = []

    def publish(self, event: FeatureGenerationCompleted) -> None:
        """Record an event publish."""
        self.events.append(event)


class RecordingFailedPublisher:
    """Records published failed events."""

    def __init__(self) -> None:
        self.events: list[FeatureGenerationFailed] = []

    def publish(self, event: FeatureGenerationFailed) -> None:
        """Record an event publish."""
        self.events.append(event)


class AssertingGeneratedPublisher(RecordingGeneratedPublisher):
    """Publisher that verifies durable state exists before publish."""

    def __init__(
        self,
        generation_repository: InMemoryFeatureGenerationRepository,
        dispatch_repository: InMemoryFeatureDispatchRepository,
        outbox_repository: InMemoryFeatureDispatchOutboxRepository,
    ) -> None:
        super().__init__()
        self._generation_repository = generation_repository
        self._dispatch_repository = dispatch_repository
        self._outbox_repository = outbox_repository

    def publish(self, event: FeatureGenerationCompleted) -> None:
        """Assert generation, dispatch, and outbox were persisted before publish."""
        generation = self._generation_repository.find(event.identifier)
        dispatch = self._dispatch_repository.find(event.identifier)
        outbox_entry = self._outbox_repository.find(event.identifier)

        assert generation is not None
        assert generation.status == FeatureGenerationStatus.GENERATED
        assert dispatch is not None
        assert dispatch.dispatch_status == DispatchStatus.PENDING
        assert outbox_entry is not None
        assert outbox_entry.status == OutboxStatus.PENDING
        super().publish(event)


class AssertingFailedPublisher(RecordingFailedPublisher):
    """Publisher that verifies durable failed state exists before publish."""

    def __init__(
        self,
        generation_repository: InMemoryFeatureGenerationRepository,
        dispatch_repository: InMemoryFeatureDispatchRepository,
        outbox_repository: InMemoryFeatureDispatchOutboxRepository,
    ) -> None:
        super().__init__()
        self._generation_repository = generation_repository
        self._dispatch_repository = dispatch_repository
        self._outbox_repository = outbox_repository

    def publish(self, event: FeatureGenerationFailed) -> None:
        """Assert failed generation, dispatch, and outbox were persisted before publish."""
        generation = self._generation_repository.find(event.identifier)
        dispatch = self._dispatch_repository.find(event.identifier)
        outbox_entry = self._outbox_repository.find(event.identifier)

        assert generation is not None
        assert generation.status == FeatureGenerationStatus.FAILED
        assert dispatch is not None
        assert dispatch.dispatch_status == DispatchStatus.PENDING
        assert outbox_entry is not None
        assert outbox_entry.status == OutboxStatus.PENDING
        super().publish(event)


class FixedClock:
    """Monotonic fixed-step clock for deterministic tests."""

    def __init__(self, start: datetime.datetime) -> None:
        self._current = start

    def __call__(self) -> datetime.datetime:
        """Return the next timestamp."""
        value = self._current
        self._current += datetime.timedelta(seconds=1)
        return value


def build_test_app() -> tuple[
    Flask,
    InMemoryFeatureGenerationRepository,
    InMemoryFeatureDispatchRepository,
    InMemoryFeatureArtifactRepository,
    InMemoryInsightRecordRepository,
    InMemoryIdempotencyKeyRepository,
    InMemoryFeatureDispatchOutboxRepository,
    RecordingGeneratedPublisher,
    RecordingFailedPublisher,
]:
    """Build the Flask app and test doubles."""
    generation_repository = InMemoryFeatureGenerationRepository()
    dispatch_repository = InMemoryFeatureDispatchRepository()
    outbox_repository = InMemoryFeatureDispatchOutboxRepository()
    artifact_repository = InMemoryFeatureArtifactRepository()
    insight_repository = InMemoryInsightRecordRepository()
    idempotency_repository = InMemoryIdempotencyKeyRepository()
    generated_publisher = RecordingGeneratedPublisher()
    failed_publisher = RecordingFailedPublisher()
    clock = FixedClock(datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC))

    service = FeatureGenerationService(
        feature_generation_repository=generation_repository,
        feature_dispatch_repository=dispatch_repository,
        feature_dispatch_outbox_repository=outbox_repository,
        feature_artifact_repository=artifact_repository,
        insight_record_repository=insight_repository,
        idempotency_key_repository=idempotency_repository,
        features_generated_publisher=generated_publisher,
        features_generation_failed_publisher=failed_publisher,
        feature_generation_factory=FeatureGenerationFactory(StubFeatureVersionGenerator()),
        feature_dispatch_factory=FeatureDispatchFactory(),
        point_in_time_join_policy=PointInTimeJoinPolicy(),
        feature_leakage_policy=FeatureLeakagePolicy(),
        feature_store_base_path="gs://alpha-mind-local/features",
        lease_seconds=300,
        clock=clock,
    )
    app = create_app(service)
    app.testing = True
    return (
        app,
        generation_repository,
        dispatch_repository,
        artifact_repository,
        insight_repository,
        idempotency_repository,
        outbox_repository,
        generated_publisher,
        failed_publisher,
    )


def build_test_app_with_order_assertion() -> tuple[
    Flask,
    InMemoryFeatureGenerationRepository,
    InMemoryFeatureDispatchRepository,
    InMemoryFeatureDispatchOutboxRepository,
    AssertingGeneratedPublisher,
    AssertingFailedPublisher,
]:
    """Build the Flask app with a publisher that asserts state-before-publish ordering."""
    generation_repository = InMemoryFeatureGenerationRepository()
    dispatch_repository = InMemoryFeatureDispatchRepository()
    outbox_repository = InMemoryFeatureDispatchOutboxRepository()
    artifact_repository = InMemoryFeatureArtifactRepository()
    insight_repository = InMemoryInsightRecordRepository()
    idempotency_repository = InMemoryIdempotencyKeyRepository()
    generated_publisher = AssertingGeneratedPublisher(
        generation_repository,
        dispatch_repository,
        outbox_repository,
    )
    failed_publisher = AssertingFailedPublisher(
        generation_repository,
        dispatch_repository,
        outbox_repository,
    )
    clock = FixedClock(datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC))

    service = FeatureGenerationService(
        feature_generation_repository=generation_repository,
        feature_dispatch_repository=dispatch_repository,
        feature_dispatch_outbox_repository=outbox_repository,
        feature_artifact_repository=artifact_repository,
        insight_record_repository=insight_repository,
        idempotency_key_repository=idempotency_repository,
        features_generated_publisher=generated_publisher,
        features_generation_failed_publisher=failed_publisher,
        feature_generation_factory=FeatureGenerationFactory(StubFeatureVersionGenerator()),
        feature_dispatch_factory=FeatureDispatchFactory(),
        point_in_time_join_policy=PointInTimeJoinPolicy(),
        feature_leakage_policy=FeatureLeakagePolicy(),
        feature_store_base_path="gs://alpha-mind-local/features",
        lease_seconds=300,
        clock=clock,
    )
    app = create_app(service)
    app.testing = True
    return app, generation_repository, dispatch_repository, outbox_repository, generated_publisher, failed_publisher


def make_push_request(envelope: dict[str, object]) -> dict[str, object]:
    """Wrap an event envelope in a Pub/Sub push request."""
    encoded = base64.b64encode(json.dumps(envelope).encode("utf-8")).decode("utf-8")
    return {
        "message": {
            "data": encoded,
            "messageId": "1001",
        },
        "subscription": "projects/alpha-mind-local/subscriptions/sub-feature-engineering-event-market-collected-v1",
    }


def make_market_collected_envelope(**payload_overrides: object) -> dict[str, object]:
    """Create a valid market.collected envelope."""
    payload = {
        "targetDate": "2026-03-05",
        "storagePath": "gs://alpha-mind-local/market/2026-03-05.parquet",
        "sourceStatus": {"jp": "ok", "us": "ok"},
    }
    payload.update(payload_overrides)
    return {
        "identifier": VALID_IDENTIFIER,
        "eventType": "market.collected",
        "occurredAt": "2026-03-05T00:10:00Z",
        "trace": VALID_TRACE,
        "schemaVersion": "1.0.0",
        "payload": payload,
    }


def test_healthz_returns_ok() -> None:
    app, *_ = build_test_app()

    response = app.test_client().get("/healthz")

    assert response.status_code == 200
    assert response.get_data(as_text=True) == "ok"


def test_pubsub_push_route_processes_market_collected_and_publishes_generated_event() -> None:
    (
        app,
        generation_repository,
        dispatch_repository,
        artifact_repository,
        _,
        idempotency_repository,
        outbox_repository,
        generated_publisher,
        failed_publisher,
    ) = build_test_app()

    response = app.test_client().post("/pubsub/push", json=make_push_request(make_market_collected_envelope()))

    assert response.status_code == 204
    assert len(generated_publisher.events) == 1
    assert len(failed_publisher.events) == 0

    generation = generation_repository.find(VALID_IDENTIFIER)
    assert generation is not None
    assert generation.status == FeatureGenerationStatus.GENERATED

    dispatch = dispatch_repository.find(VALID_IDENTIFIER)
    assert dispatch is not None
    assert dispatch.dispatch_status == DispatchStatus.PUBLISHED
    assert dispatch.published_event == PublishedEventType.FEATURES_GENERATED
    outbox_entry = outbox_repository.find(VALID_IDENTIFIER)
    assert outbox_entry is not None
    assert outbox_entry.status == OutboxStatus.PUBLISHED

    assert artifact_repository.find("v20260305-001") is not None
    assert idempotency_repository.find(VALID_IDENTIFIER) is not None
    published_event = generated_publisher.events[0]
    assert published_event.trace == VALID_TRACE


def test_root_path_is_alias_for_pubsub_push() -> None:
    app, *_ = build_test_app()

    response = app.test_client().post("/", json=make_push_request(make_market_collected_envelope()))

    assert response.status_code == 204


def test_missing_storage_path_publishes_failed_event_and_persists_failed_state() -> None:
    app, generation_repository, dispatch_repository, _, _, _, outbox_repository, generated_publisher, failed_publisher = (
        build_test_app()
    )

    response = app.test_client().post(
        "/pubsub/push",
        json=make_push_request(make_market_collected_envelope(storagePath="")),
    )

    assert response.status_code == 204
    assert len(generated_publisher.events) == 0
    assert len(failed_publisher.events) == 1

    generation = generation_repository.find(VALID_IDENTIFIER)
    assert generation is not None
    assert generation.status == FeatureGenerationStatus.FAILED
    assert generation.failure_detail is not None
    assert generation.failure_detail.reason_code == ReasonCode.REQUEST_VALIDATION_FAILED

    dispatch = dispatch_repository.find(VALID_IDENTIFIER)
    assert dispatch is not None
    assert dispatch.dispatch_status == DispatchStatus.PUBLISHED
    assert dispatch.published_event == PublishedEventType.FEATURES_GENERATION_FAILED
    outbox_entry = outbox_repository.find(VALID_IDENTIFIER)
    assert outbox_entry is not None
    assert outbox_entry.status == OutboxStatus.PUBLISHED

    published_event = failed_publisher.events[0]
    assert published_event.trace == VALID_TRACE
    assert published_event.reason_code == ReasonCode.REQUEST_VALIDATION_FAILED


def test_duplicate_delivery_is_acked_without_duplicate_publish() -> None:
    app, _, _, _, _, _, _, generated_publisher, failed_publisher = build_test_app()
    client = app.test_client()
    request_body = make_push_request(make_market_collected_envelope())

    first = client.post("/pubsub/push", json=request_body)
    second = client.post("/pubsub/push", json=request_body)

    assert first.status_code == 204
    assert second.status_code == 204
    assert len(generated_publisher.events) == 1
    assert len(failed_publisher.events) == 0


def test_invalid_schema_version_returns_problem_details() -> None:
    app, *_ = build_test_app()
    envelope = make_market_collected_envelope()
    envelope["schemaVersion"] = "1.0"

    response = app.test_client().post("/pubsub/push", json=make_push_request(envelope))

    assert response.status_code == 400
    assert response.headers["Content-Type"].startswith("application/problem+json")
    body = response.get_json()
    assert body["title"] == "Bad Request"
    assert body["status"] == 400
    assert body["reasonCode"] == "REQUEST_VALIDATION_FAILED"
    assert body["trace"] == VALID_TRACE
    assert body["retryable"] is False


def test_future_insight_data_publishes_failed_event() -> None:
    (
        app,
        generation_repository,
        dispatch_repository,
        _,
        insight_repository,
        _,
        _,
        generated_publisher,
        failed_publisher,
    ) = build_test_app()
    insight_repository.snapshot = InsightSnapshot(
        record_count=1,
        latest_collected_at=datetime.datetime(2026, 3, 6, 0, 0, 1, tzinfo=datetime.UTC),
        filtered_by_target_date=True,
    )

    response = app.test_client().post("/pubsub/push", json=make_push_request(make_market_collected_envelope()))

    assert response.status_code == 204
    assert len(generated_publisher.events) == 0
    assert len(failed_publisher.events) == 1
    generation = generation_repository.find(VALID_IDENTIFIER)
    assert generation is not None
    assert generation.status == FeatureGenerationStatus.FAILED
    assert generation.failure_detail is not None
    assert generation.failure_detail.reason_code == ReasonCode.DATA_QUALITY_LEAK_DETECTED
    dispatch = dispatch_repository.find(VALID_IDENTIFIER)
    assert dispatch is not None
    assert dispatch.published_event == PublishedEventType.FEATURES_GENERATION_FAILED


def test_publish_happens_after_generation_dispatch_and_outbox_are_persisted() -> None:
    app, _, _, outbox_repository, generated_publisher, _ = build_test_app_with_order_assertion()

    response = app.test_client().post("/pubsub/push", json=make_push_request(make_market_collected_envelope()))

    assert response.status_code == 204
    assert len(generated_publisher.events) == 1
    outbox_entry = outbox_repository.find(VALID_IDENTIFIER)
    assert outbox_entry is not None
    assert outbox_entry.status == OutboxStatus.PUBLISHED


def test_failed_publish_happens_after_generation_dispatch_and_outbox_are_persisted() -> None:
    app, _, _, outbox_repository, _, failed_publisher = build_test_app_with_order_assertion()

    response = app.test_client().post(
        "/pubsub/push",
        json=make_push_request(make_market_collected_envelope(storagePath="")),
    )

    assert response.status_code == 204
    assert len(failed_publisher.events) == 1
    outbox_entry = outbox_repository.find(VALID_IDENTIFIER)
    assert outbox_entry is not None
    assert outbox_entry.status == OutboxStatus.PUBLISHED
