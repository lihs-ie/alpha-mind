"""SG-IT-003: 入力欠損の統合テスト。

観点: featureVersion が欠損した features.generated イベントを受信し、
      signal.generation.failed イベントが発行されること。
優先度: P0
"""

from __future__ import annotations

import json

import flask.testing
import pytest
from google.cloud.firestore_v1 import Client as FirestoreClient
from google.cloud.pubsub_v1 import SubscriberClient

from tests.integration.conftest import (
    TEST_FEATURE_STORAGE_PATH,
    build_cloud_event,
    build_pubsub_push_body,
    drain_subscription,
    pull_messages,
    seed_approved_model,
)


class TestInputDeficiencyIntegration:
    """SG-IT-003: 入力欠損フローの統合テスト。"""

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

    def test_missing_feature_version_returns_200_ack(
        self,
        client: flask.testing.FlaskClient,
    ) -> None:
        """featureVersion 欠損時に HTTP 200 (ack) を返す。

        featureVersion が欠損した場合、CloudEvent デコーダーがバリデーション
        エラーを検出し、非再試行の ack (200) を返す。
        """
        payload: dict[str, object] = {
            "targetDate": "2026-03-05",
            # featureVersion を意図的に欠損させる
            "storagePath": TEST_FEATURE_STORAGE_PATH,
        }
        cloud_event = build_cloud_event(
            identifier="01ARZ3NDEKTSV4RRFFQ69G5FAD",
            trace="01ARZ3NDEKTSV4RRFFQ69G5FAD",
            occurred_at="2026-03-05T00:21:00Z",
            payload=payload,
        )
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)

        # featureVersion が欠損しているため CloudEvent デコーダーでエラーになる
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data["status"] == "error"

    def test_missing_storage_path_returns_200_ack(
        self,
        client: flask.testing.FlaskClient,
    ) -> None:
        """storagePath 欠損時に HTTP 200 (ack) を返す。"""
        payload: dict[str, object] = {
            "targetDate": "2026-03-05",
            "featureVersion": "feature-v1",
            # storagePath を意図的に欠損させる
        }
        cloud_event = build_cloud_event(
            identifier="01ARZ3NDEKTSV4RRFFQ69G5FAE",
            trace="01ARZ3NDEKTSV4RRFFQ69G5FAE",
            payload=payload,
        )
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)

        assert response.status_code == 200
        data = json.loads(response.data)
        assert data["status"] == "error"

    def test_missing_target_date_returns_200_ack(
        self,
        client: flask.testing.FlaskClient,
    ) -> None:
        """targetDate 欠損時に HTTP 200 (ack) を返す。"""
        payload: dict[str, object] = {
            # targetDate を意図的に欠損させる
            "featureVersion": "feature-v1",
            "storagePath": TEST_FEATURE_STORAGE_PATH,
        }
        cloud_event = build_cloud_event(
            identifier="01ARZ3NDEKTSV4RRFFQ69G5FAF",
            trace="01ARZ3NDEKTSV4RRFFQ69G5FAF",
            payload=payload,
        )
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)

        assert response.status_code == 200
        data = json.loads(response.data)
        assert data["status"] == "error"

    def test_invalid_storage_path_triggers_failed_event(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_failed_subscription: str,
    ) -> None:
        """storagePath が不正な場合に signal.generation.failed イベントが発行される。

        storagePath が gs:// で始まらない不正な値の場合、CloudEvent デコーダーは
        通過するがFeaturePayloadIntegritySpecification で検証失敗となり、
        signal.generation.failed が発行される。
        """
        payload: dict[str, object] = {
            "targetDate": "2026-03-05",
            "featureVersion": "feature-v1",
            "storagePath": "invalid://path/to/features.parquet",
        }
        cloud_event = build_cloud_event(
            identifier="01ARZ3NDEKTSV4RRFFQ69G5FAG",
            trace="01ARZ3NDEKTSV4RRFFQ69G5FAG",
            payload=payload,
        )
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)
        assert response.status_code == 200

        messages = pull_messages(subscriber_client, signal_failed_subscription)

        assert len(messages) == 1
        failed_event = messages[0]
        assert failed_event["eventType"] == "signal.generation.failed"
        assert failed_event["identifier"] == "01ARZ3NDEKTSV4RRFFQ69G5FAG"
        assert failed_event["payload"]["reasonCode"] == "REQUEST_VALIDATION_FAILED"

    def test_no_approved_model_triggers_failed_event(
        self,
        client: flask.testing.FlaskClient,
        firestore_client: FirestoreClient,
        subscriber_client: SubscriberClient,
        signal_failed_subscription: str,
    ) -> None:
        """approved モデルが存在しない場合に signal.generation.failed イベントが発行される。"""
        # approved モデルを削除して model_registry を空にする
        _delete_collection(firestore_client, "model_registry")

        cloud_event = build_cloud_event(
            identifier="01ARZ3NDEKTSV4RRFFQ69G5FAH",
            trace="01ARZ3NDEKTSV4RRFFQ69G5FAH",
        )
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)
        assert response.status_code == 200

        messages = pull_messages(subscriber_client, signal_failed_subscription)

        assert len(messages) == 1
        failed_event = messages[0]
        assert failed_event["eventType"] == "signal.generation.failed"
        assert failed_event["payload"]["reasonCode"] == "MODEL_NOT_APPROVED"

    def test_does_not_publish_signal_generated_on_input_deficiency(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """入力欠損時に signal.generated イベントが発行されない。"""
        payload: dict[str, object] = {
            "targetDate": "2026-03-05",
            "featureVersion": "feature-v1",
            "storagePath": "invalid://path/features.parquet",
        }
        cloud_event = build_cloud_event(
            identifier="01ARZ3NDEKTSV4RRFFQ69G5FAJ",
            trace="01ARZ3NDEKTSV4RRFFQ69G5FAJ",
            payload=payload,
        )
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)
        assert response.status_code == 200

        messages = pull_messages(subscriber_client, signal_generated_subscription, timeout_seconds=3.0)
        assert len(messages) == 0


def _delete_collection(client: FirestoreClient, collection_name: str) -> None:
    """Firestore コレクションの全ドキュメントを削除する。"""
    collection_reference = client.collection(collection_name)
    documents = list(collection_reference.limit(500).stream())
    for document in documents:
        document.reference.delete()
