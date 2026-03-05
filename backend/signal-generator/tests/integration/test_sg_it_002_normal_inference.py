"""SG-IT-002: 正常推論の統合テスト。

観点: features.generated イベントを受信し、正常に推論を実行して
      signal.generated イベントが発行されること。
優先度: P0
"""

from __future__ import annotations

import json
from typing import cast

import flask.testing
import pytest
from google.cloud.firestore_v1 import Client as FirestoreClient
from google.cloud.firestore_v1.base_document import DocumentSnapshot
from google.cloud.pubsub_v1 import SubscriberClient

from tests.integration.conftest import (
    build_cloud_event,
    build_pubsub_push_body,
    drain_subscription,
    pull_messages,
    seed_approved_model,
)


class TestNormalInferenceIntegration:
    """SG-IT-002: 正常推論フローの統合テスト。"""

    @pytest.fixture(autouse=True)
    def _setup(
        self,
        firestore_client: FirestoreClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
        signal_failed_subscription: str,
    ) -> None:
        """各テスト前に approved モデルを登録し、サブスクリプションを排出する。"""
        seed_approved_model(firestore_client)
        drain_subscription(subscriber_client, signal_generated_subscription)
        drain_subscription(subscriber_client, signal_failed_subscription)

    def test_returns_200_on_valid_features_generated_event(
        self,
        client: flask.testing.FlaskClient,
    ) -> None:
        """正常な features.generated イベントに対して HTTP 200 を返す。"""
        cloud_event = build_cloud_event()
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)

        assert response.status_code == 200
        data = json.loads(response.data)
        assert data["status"] == "ok"

    def test_publishes_signal_generated_event(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """正常推論後に signal.generated イベントが Pub/Sub に発行される。"""
        cloud_event = build_cloud_event()
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)
        assert response.status_code == 200

        messages = pull_messages(subscriber_client, signal_generated_subscription)

        assert len(messages) == 1
        signal_event = messages[0]
        assert signal_event["eventType"] == "signal.generated"
        assert signal_event["identifier"] == "01ARZ3NDEKTSV4RRFFQ69G5FAC"
        assert signal_event["trace"] == "01ARZ3NDEKTSV4RRFFQ69G5FAC"

    def test_signal_generated_payload_contains_required_fields(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """signal.generated ペイロードに必須フィールドが含まれる。"""
        cloud_event = build_cloud_event()
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)
        assert response.status_code == 200

        messages = pull_messages(subscriber_client, signal_generated_subscription)
        assert len(messages) == 1

        payload = messages[0]["payload"]
        assert "signalVersion" in payload
        assert "modelVersion" in payload
        assert "featureVersion" in payload
        assert "storagePath" in payload
        assert "modelDiagnostics" in payload

    def test_signal_generated_has_schema_version(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """signal.generated イベントに schemaVersion が含まれる。"""
        cloud_event = build_cloud_event()
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)
        assert response.status_code == 200

        messages = pull_messages(subscriber_client, signal_generated_subscription)
        assert len(messages) == 1
        assert messages[0]["schemaVersion"] == "1.0.0"

    def test_persists_signal_generation_to_firestore(
        self,
        client: flask.testing.FlaskClient,
        firestore_client: FirestoreClient,
    ) -> None:
        """正常推論後に SignalGeneration 集約が Firestore に永続化される。"""
        cloud_event = build_cloud_event()
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)
        assert response.status_code == 200

        document = cast(
            DocumentSnapshot,
            firestore_client.collection("signal_generations").document("01ARZ3NDEKTSV4RRFFQ69G5FAC").get(),
        )
        assert document.exists
        document_data = document.to_dict()
        assert document_data is not None
        assert document_data["status"] == "generated"

    def test_persists_signal_dispatch_to_firestore(
        self,
        client: flask.testing.FlaskClient,
        firestore_client: FirestoreClient,
    ) -> None:
        """正常推論後に SignalDispatch 集約が Firestore に永続化される。"""
        cloud_event = build_cloud_event()
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)
        assert response.status_code == 200

        document = cast(
            DocumentSnapshot,
            firestore_client.collection("signal_dispatches").document("01ARZ3NDEKTSV4RRFFQ69G5FAC").get(),
        )
        assert document.exists
        document_data = document.to_dict()
        assert document_data is not None
        assert document_data["dispatchStatus"] == "published"
        assert document_data["publishedEvent"] == "signal.generated"

    def test_persists_idempotency_key_to_firestore(
        self,
        client: flask.testing.FlaskClient,
        firestore_client: FirestoreClient,
    ) -> None:
        """正常推論後に冪等性キーが Firestore に永続化される。"""
        cloud_event = build_cloud_event()
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)
        assert response.status_code == 200

        document = cast(
            DocumentSnapshot,
            firestore_client.collection("idempotency_keys")
            .document("signal-generator:01ARZ3NDEKTSV4RRFFQ69G5FAC")
            .get(),
        )
        assert document.exists

    def test_does_not_publish_failed_event_on_success(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_failed_subscription: str,
    ) -> None:
        """正常推論時に signal.generation.failed イベントが発行されない。"""
        cloud_event = build_cloud_event()
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)
        assert response.status_code == 200

        messages = pull_messages(subscriber_client, signal_failed_subscription, timeout_seconds=3.0)
        assert len(messages) == 0
