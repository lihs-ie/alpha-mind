"""SG-IT-005: 監査属性の統合テスト。

観点: signal.generated ペイロードに modelVersion, featureVersion, trace が
      正しく保持されていること。
優先度: P0
"""

from __future__ import annotations

from typing import Any, cast

import flask.testing
import pytest
from google.cloud.firestore_v1 import Client as FirestoreClient
from google.cloud.firestore_v1.base_document import DocumentSnapshot
from google.cloud.pubsub_v1 import SubscriberClient

from tests.integration.conftest import (
    TEST_FEATURE_STORAGE_PATH,
    TEST_MODEL_VERSION,
    build_cloud_event,
    build_pubsub_push_body,
    drain_subscription,
    pull_messages,
    seed_approved_model,
)


class TestAuditAttributesIntegration:
    """SG-IT-005: 監査属性の統合テスト。"""

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

    def _execute_normal_inference(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
        *,
        identifier: str = "01ARZ3NDEKTSV4RRFFQ69G5FAW",
        trace: str = "01ARZ3NDEKTSV4RRFFQ69G5FAW",
        feature_version: str = "feature-v1",
    ) -> dict[str, Any]:
        """正常推論を実行し、signal.generated イベントを返す。"""
        payload: dict[str, object] = {
            "targetDate": "2026-03-05",
            "featureVersion": feature_version,
            "storagePath": TEST_FEATURE_STORAGE_PATH,
        }
        cloud_event = build_cloud_event(
            identifier=identifier,
            trace=trace,
            payload=payload,
        )
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)
        assert response.status_code == 200

        messages = pull_messages(subscriber_client, signal_generated_subscription)
        assert len(messages) == 1
        return messages[0]

    def test_signal_generated_contains_model_version(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """signal.generated ペイロードに modelVersion が含まれる。"""
        signal_event = self._execute_normal_inference(
            client,
            subscriber_client,
            signal_generated_subscription,
            identifier="01ARZ3NDEKTSV4RRFFQ69G5FA1",
            trace="01ARZ3NDEKTSV4RRFFQ69G5FA1",
        )

        payload = signal_event["payload"]
        assert "modelVersion" in payload
        assert payload["modelVersion"] == TEST_MODEL_VERSION

    def test_signal_generated_contains_feature_version(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """signal.generated ペイロードに featureVersion が含まれる。"""
        signal_event = self._execute_normal_inference(
            client,
            subscriber_client,
            signal_generated_subscription,
            identifier="01ARZ3NDEKTSV4RRFFQ69G5FA2",
            trace="01ARZ3NDEKTSV4RRFFQ69G5FA2",
            feature_version="feature-v1",
        )

        payload = signal_event["payload"]
        assert "featureVersion" in payload
        assert payload["featureVersion"] == "feature-v1"

    def test_signal_generated_preserves_trace(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """signal.generated イベントの trace が入力イベントの trace と一致する。"""
        input_trace = "01ARZ3NDEKTSV4RRFFQ69G5FA3"
        signal_event = self._execute_normal_inference(
            client,
            subscriber_client,
            signal_generated_subscription,
            identifier="01ARZ3NDEKTSV4RRFFQ69G5FA3",
            trace=input_trace,
        )

        assert signal_event["trace"] == input_trace

    def test_signal_generated_contains_model_diagnostics(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """signal.generated ペイロードに modelDiagnostics が含まれる (RULE-SG-006)。"""
        signal_event = self._execute_normal_inference(
            client,
            subscriber_client,
            signal_generated_subscription,
            identifier="01ARZ3NDEKTSV4RRFFQ69G5FA4",
            trace="01ARZ3NDEKTSV4RRFFQ69G5FA4",
        )

        payload = signal_event["payload"]
        assert "modelDiagnostics" in payload
        diagnostics = payload["modelDiagnostics"]
        assert "degradationFlag" in diagnostics
        assert "requiresComplianceReview" in diagnostics

    def test_signal_generated_contains_storage_path(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """signal.generated ペイロードに storagePath が含まれる。"""
        signal_event = self._execute_normal_inference(
            client,
            subscriber_client,
            signal_generated_subscription,
            identifier="01ARZ3NDEKTSV4RRFFQ69G5FA5",
            trace="01ARZ3NDEKTSV4RRFFQ69G5FA5",
        )

        payload = signal_event["payload"]
        assert "storagePath" in payload
        assert payload["storagePath"].startswith("gs://")

    def test_signal_generated_contains_occurred_at(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """signal.generated イベントに occurredAt (ISO8601) が含まれる。"""
        signal_event = self._execute_normal_inference(
            client,
            subscriber_client,
            signal_generated_subscription,
            identifier="01ARZ3NDEKTSV4RRFFQ69G5FA6",
            trace="01ARZ3NDEKTSV4RRFFQ69G5FA6",
        )

        assert "occurredAt" in signal_event
        occurred_at = signal_event["occurredAt"]
        assert isinstance(occurred_at, str)
        # ISO8601 形式であることを簡易検証
        assert "T" in occurred_at

    def test_signal_generated_contains_identifier(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """signal.generated イベントの identifier が入力と一致する。"""
        input_identifier = "01ARZ3NDEKTSV4RRFFQ69G5FA7"
        signal_event = self._execute_normal_inference(
            client,
            subscriber_client,
            signal_generated_subscription,
            identifier=input_identifier,
            trace=input_identifier,
        )

        assert signal_event["identifier"] == input_identifier

    def test_firestore_signal_generation_contains_audit_attributes(
        self,
        client: flask.testing.FlaskClient,
        firestore_client: FirestoreClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """Firestore の signal_generations ドキュメントに監査属性が含まれる。"""
        identifier = "01ARZ3NDEKTSV4RRFFQ69G5FA8"
        self._execute_normal_inference(
            client,
            subscriber_client,
            signal_generated_subscription,
            identifier=identifier,
            trace=identifier,
            feature_version="feature-v1",
        )

        document = cast(
            DocumentSnapshot,
            firestore_client.collection("signal_generations").document(identifier).get(),
        )
        assert document.exists
        document_data = document.to_dict()
        assert document_data is not None

        # 監査属性の存在を検証
        assert document_data["trace"] == identifier
        assert document_data["featureSnapshot"]["featureVersion"] == "feature-v1"
        assert document_data["modelSnapshot"]["modelVersion"] == TEST_MODEL_VERSION
        assert document_data["signalArtifact"]["signalVersion"] is not None

    def test_failed_event_preserves_trace(
        self,
        client: flask.testing.FlaskClient,
        firestore_client: FirestoreClient,
        subscriber_client: SubscriberClient,
        signal_failed_subscription: str,
    ) -> None:
        """signal.generation.failed イベントの trace が入力イベントの trace と一致する。"""
        # model_registry を空にして MODEL_NOT_APPROVED を誘発
        _delete_collection(firestore_client, "model_registry")

        input_trace = "01ARZ3NDEKTSV4RRFFQ69G5FA9"
        cloud_event = build_cloud_event(
            identifier="01ARZ3NDEKTSV4RRFFQ69G5FA9",
            trace=input_trace,
        )
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)
        assert response.status_code == 200

        messages = pull_messages(subscriber_client, signal_failed_subscription)
        assert len(messages) == 1
        assert messages[0]["trace"] == input_trace


def _delete_collection(client: FirestoreClient, collection_name: str) -> None:
    """Firestore コレクションの全ドキュメントを削除する。"""
    collection_reference = client.collection(collection_name)
    documents = list(collection_reference.limit(500).stream())
    for document in documents:
        document.reference.delete()
