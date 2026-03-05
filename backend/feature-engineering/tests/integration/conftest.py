"""Integration test fixtures using real GCP emulators (no mocks).

Uses the existing docker/docker-compose.yml emulators:
- Firestore emulator on localhost:8080
- Pub/Sub emulator on localhost:8085
- fake-gcs-server on localhost:4443
"""

from __future__ import annotations

import contextlib
import os
from typing import Any

import flask
import flask.testing
import pytest
from google.cloud import firestore, storage  # type: ignore[attr-defined]
from google.cloud.pubsub_v1 import PublisherClient, SubscriberClient
from tests.integration.helpers import (
    FEATURE_STORE_BUCKET,
    FEATURES_GENERATED_TOPIC,
    FEATURES_GENERATION_FAILED_TOPIC,
    PROJECT_ID,
)

from presentation.app_factory import create_application
from presentation.dependency_container import DependencyContainer


@pytest.fixture(scope="session", autouse=True)
def emulator_environment() -> None:
    """Set environment variables for GCP emulators (docker/docker-compose.yml)."""
    os.environ["FIRESTORE_EMULATOR_HOST"] = "localhost:8080"
    os.environ["PUBSUB_EMULATOR_HOST"] = "localhost:8085"
    os.environ["STORAGE_EMULATOR_HOST"] = "http://localhost:4443"
    os.environ["GCP_PROJECT_ID"] = PROJECT_ID
    os.environ["FEATURES_GENERATED_TOPIC"] = FEATURES_GENERATED_TOPIC
    os.environ["FEATURES_GENERATION_FAILED_TOPIC"] = FEATURES_GENERATION_FAILED_TOPIC
    os.environ["FEATURE_STORE_BUCKET"] = FEATURE_STORE_BUCKET


@pytest.fixture(scope="session")
def firestore_client(emulator_environment: None) -> firestore.Client:
    return firestore.Client(project=PROJECT_ID)


@pytest.fixture(scope="session")
def publisher_client(emulator_environment: None) -> PublisherClient:
    return PublisherClient()


@pytest.fixture(scope="session")
def subscriber_client(emulator_environment: None) -> SubscriberClient:
    return SubscriberClient()


@pytest.fixture(scope="session")
def storage_client(emulator_environment: None) -> storage.Client:
    return storage.Client(project=PROJECT_ID)


@pytest.fixture(scope="session")
def pubsub_topics(publisher_client: PublisherClient) -> dict[str, str]:
    """Ensure Pub/Sub topics exist and return topic name -> topic path mapping."""
    topics: dict[str, str] = {}
    for topic_name in [FEATURES_GENERATED_TOPIC, FEATURES_GENERATION_FAILED_TOPIC]:
        topic_path = publisher_client.topic_path(PROJECT_ID, topic_name)
        with contextlib.suppress(Exception):
            publisher_client.create_topic(request={"name": topic_path})
        topics[topic_name] = topic_path
    return topics


@pytest.fixture(scope="session")
def pubsub_subscriptions(
    subscriber_client: SubscriberClient,
    pubsub_topics: dict[str, str],
) -> dict[str, str]:
    """Create pull subscriptions for integration test verification."""
    subscriptions: dict[str, str] = {}
    for topic_name, topic_path in pubsub_topics.items():
        subscription_name = f"sub-integration-test-{topic_name}"
        subscription_path = subscriber_client.subscription_path(PROJECT_ID, subscription_name)
        with contextlib.suppress(Exception):
            subscriber_client.create_subscription(
                request={
                    "name": subscription_path,
                    "topic": topic_path,
                    "ack_deadline_seconds": 60,
                }
            )
        subscriptions[topic_name] = subscription_path
    return subscriptions


@pytest.fixture(scope="session")
def flask_application(
    emulator_environment: None,
    pubsub_subscriptions: dict[str, str],
) -> flask.Flask:
    """Create Flask application wired to real emulators via DependencyContainer."""
    container = DependencyContainer()
    service = container.feature_generation_service()
    return create_application(service)


@pytest.fixture()
def test_client(flask_application: flask.Flask) -> flask.testing.FlaskClient:
    return flask_application.test_client()


@pytest.fixture()
def cleanup_firestore(firestore_client: firestore.Client) -> Any:
    """Clean up Firestore collections after each test."""
    yield
    collections = [
        "idempotency_keys",
        "feature_generations",
        "feature_dispatches",
        "insight_records",
    ]
    for collection_name in collections:
        for document in firestore_client.collection(collection_name).stream():
            document.reference.delete()
