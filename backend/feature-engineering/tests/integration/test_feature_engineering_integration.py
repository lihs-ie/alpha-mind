"""Integration tests for feature-engineering service.

Test cases FE-IT-001 through FE-IT-005 from the test design document.
All tests use real GCP emulators (Firestore, Pub/Sub, GCS) — no mocks.

Requires Docker emulators running:
    cd docker && docker compose up -d
"""

from __future__ import annotations

import flask.testing
import pytest
from google.cloud import firestore, storage  # type: ignore[attr-defined]
from google.cloud.pubsub_v1 import SubscriberClient
from tests.integration.helpers import (
    FEATURE_STORE_BUCKET,
    FEATURES_GENERATED_TOPIC,
    FEATURES_GENERATION_FAILED_TOPIC,
    build_pubsub_push_body,
    drain_subscription,
    pull_messages,
)


@pytest.mark.integration
class TestFEIT001HealthCheck:
    """FE-IT-001: Health check endpoint returns 200 with status ok."""

    def test_healthz_returns_ok(
        self,
        test_client: flask.testing.FlaskClient,
    ) -> None:
        response = test_client.get("/healthz")

        assert response.status_code == 200
        data = response.get_json()
        assert data is not None
        assert data["status"] == "ok"
        assert "time" in data


@pytest.mark.integration
class TestFEIT002NormalFeatureGeneration:
    """FE-IT-002: Normal feature generation produces features.generated event."""

    def test_market_collected_produces_features_generated(
        self,
        test_client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        firestore_client: firestore.Client,
        storage_client: storage.Client,
        pubsub_subscriptions: dict[str, str],
        cleanup_firestore: None,
    ) -> None:
        subscription_path = pubsub_subscriptions[FEATURES_GENERATED_TOPIC]
        drain_subscription(subscriber_client, subscription_path)

        cloud_event = {
            "identifier": "01ARZ3NDEKTSV4RRFFQ69G5FAA",
            "eventType": "market.collected",
            "occurredAt": "2026-03-05T00:10:00Z",
            "trace": "01ARZ3NDEKTSV4RRFFQ69G5FAA",
            "schemaVersion": "1.0.0",
            "payload": {
                "targetDate": "2026-03-05",
                "storagePath": "gs://alpha-mind-local/market/2026-03-05.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            },
        }
        body = build_pubsub_push_body(cloud_event)

        response = test_client.post("/", json=body, content_type="application/json")

        assert response.status_code == 204

        messages = pull_messages(subscriber_client, subscription_path)
        assert len(messages) == 1

        event = messages[0]
        assert event["eventType"] == "features.generated"
        assert event["identifier"] == "01ARZ3NDEKTSV4RRFFQ69G5FAA"
        assert event["trace"] == "01ARZ3NDEKTSV4RRFFQ69G5FAA"
        assert "featureVersion" in event["payload"]
        assert "storagePath" in event["payload"]
        assert event["payload"]["targetDate"] == "2026-03-05"

        generation_document = (
            firestore_client.collection("feature_generations").document("01ARZ3NDEKTSV4RRFFQ69G5FAA").get()
        )
        assert generation_document.exists
        generation_data = generation_document.to_dict()
        assert generation_data is not None
        assert generation_data["status"] == "generated"

        dispatch_document = (
            firestore_client.collection("feature_dispatches").document("01ARZ3NDEKTSV4RRFFQ69G5FAA").get()
        )
        assert dispatch_document.exists
        dispatch_data = dispatch_document.to_dict()
        assert dispatch_data is not None
        assert dispatch_data["dispatchStatus"] == "published"

        idempotency_document = (
            firestore_client.collection("idempotency_keys")
            .document("feature-engineering:01ARZ3NDEKTSV4RRFFQ69G5FAA")
            .get()
        )
        assert idempotency_document.exists

        feature_version = event["payload"]["featureVersion"]
        bucket = storage_client.bucket(FEATURE_STORE_BUCKET)
        blob = bucket.blob(f"{feature_version}/metadata.json")
        assert blob.exists()


@pytest.mark.integration
class TestFEIT003InputDeficiency:
    """FE-IT-003: Input deficiency handling.

    Two sub-cases tested:
    - storagePath missing: decoder rejects with HTTP 400 (no event published)
    - sourceStatus unhealthy: domain failure produces features.generation.failed
    """

    def test_missing_storage_path_returns_400(
        self,
        test_client: flask.testing.FlaskClient,
    ) -> None:
        cloud_event = {
            "identifier": "01ARZ3NDEKTSV4RRFFQ69G5FAB",
            "eventType": "market.collected",
            "occurredAt": "2026-03-05T00:11:00Z",
            "trace": "01ARZ3NDEKTSV4RRFFQ69G5FAB",
            "schemaVersion": "1.0.0",
            "payload": {
                "targetDate": "2026-03-05",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            },
        }
        body = build_pubsub_push_body(cloud_event)

        response = test_client.post("/", json=body, content_type="application/json")

        assert response.status_code == 400

    def test_unhealthy_source_produces_features_generation_failed(
        self,
        test_client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        pubsub_subscriptions: dict[str, str],
        cleanup_firestore: None,
    ) -> None:
        subscription_path = pubsub_subscriptions[FEATURES_GENERATION_FAILED_TOPIC]
        drain_subscription(subscriber_client, subscription_path)

        cloud_event = {
            "identifier": "01ARZ3NDEKTSV4RRFFQ69G5FAC",
            "eventType": "market.collected",
            "occurredAt": "2026-03-05T00:12:00Z",
            "trace": "01ARZ3NDEKTSV4RRFFQ69G5FAC",
            "schemaVersion": "1.0.0",
            "payload": {
                "targetDate": "2026-03-05",
                "storagePath": "gs://alpha-mind-local/market/2026-03-05.parquet",
                "sourceStatus": {"jp": "failed", "us": "ok"},
            },
        }
        body = build_pubsub_push_body(cloud_event)

        response = test_client.post("/", json=body, content_type="application/json")

        # sourceStatus unhealthy → retryable failure → HTTP 500
        assert response.status_code == 500

        messages = pull_messages(subscriber_client, subscription_path)
        assert len(messages) == 1

        event = messages[0]
        assert event["eventType"] == "features.generation.failed"
        assert event["identifier"] == "01ARZ3NDEKTSV4RRFFQ69G5FAC"
        assert event["payload"]["reasonCode"] == "DEPENDENCY_UNAVAILABLE"


@pytest.mark.integration
class TestFEIT004Idempotency:
    """FE-IT-004: Same identifier sent twice does not produce duplicate events."""

    def test_duplicate_identifier_does_not_produce_duplicate_event(
        self,
        test_client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        pubsub_subscriptions: dict[str, str],
        cleanup_firestore: None,
    ) -> None:
        subscription_path = pubsub_subscriptions[FEATURES_GENERATED_TOPIC]
        drain_subscription(subscriber_client, subscription_path)

        cloud_event = {
            "identifier": "01ARZ3NDEKTSV4RRFFQ69G5FAD",
            "eventType": "market.collected",
            "occurredAt": "2026-03-05T00:13:00Z",
            "trace": "01ARZ3NDEKTSV4RRFFQ69G5FAD",
            "schemaVersion": "1.0.0",
            "payload": {
                "targetDate": "2026-03-05",
                "storagePath": "gs://alpha-mind-local/market/2026-03-05.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            },
        }
        body = build_pubsub_push_body(cloud_event)

        # First request: should succeed
        response_1 = test_client.post("/", json=body, content_type="application/json")
        assert response_1.status_code == 204

        # Consume the first event
        first_messages = pull_messages(subscriber_client, subscription_path)
        assert len(first_messages) == 1

        # Drain to ensure clean state
        drain_subscription(subscriber_client, subscription_path)

        # Second request with same identifier: idempotent no-op
        response_2 = test_client.post("/", json=body, content_type="application/json")
        assert response_2.status_code == 204

        # No new event should be published
        duplicate_messages = pull_messages(subscriber_client, subscription_path, timeout=2.0)
        assert len(duplicate_messages) == 0


@pytest.mark.integration
class TestFEIT005TracePropagation:
    """FE-IT-005: Output event trace matches input trace."""

    def test_trace_propagated_to_output_event(
        self,
        test_client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        pubsub_subscriptions: dict[str, str],
        cleanup_firestore: None,
    ) -> None:
        subscription_path = pubsub_subscriptions[FEATURES_GENERATED_TOPIC]
        drain_subscription(subscriber_client, subscription_path)

        input_trace = "01ARZ3NDEKTSV4RRFFQ69G5FBB"
        cloud_event = {
            "identifier": "01ARZ3NDEKTSV4RRFFQ69G5FAE",
            "eventType": "market.collected",
            "occurredAt": "2026-03-05T00:15:00Z",
            "trace": input_trace,
            "schemaVersion": "1.0.0",
            "payload": {
                "targetDate": "2026-03-05",
                "storagePath": "gs://alpha-mind-local/market/2026-03-05.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            },
        }
        body = build_pubsub_push_body(cloud_event)

        response = test_client.post("/", json=body, content_type="application/json")
        assert response.status_code == 204

        messages = pull_messages(subscriber_client, subscription_path)
        assert len(messages) == 1

        event = messages[0]
        assert event["trace"] == input_trace
