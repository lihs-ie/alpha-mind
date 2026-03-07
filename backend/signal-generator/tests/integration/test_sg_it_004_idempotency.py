"""SG-IT-004: 冪等性の統合テスト。

観点: 同一 identifier のイベントを複数回送信しても出力が重複しないこと。
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


class TestIdempotencyIntegration:
    """SG-IT-004: 冪等性の統合テスト。"""

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

    def test_duplicate_event_returns_200_without_duplicate_output(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """同一 identifier のイベントを2回送信しても signal.generated は1件のみ発行される。"""
        identifier = "01ARZ3NDEKTSV4RRFFQ69G5FAQ"
        cloud_event = build_cloud_event(
            identifier=identifier,
            trace=identifier,
        )
        body = build_pubsub_push_body(cloud_event)

        # 1回目: 正常処理
        first_response = client.post("/", json=body)
        assert first_response.status_code == 200
        first_data = json.loads(first_response.data)
        assert first_data["status"] == "ok"

        # 1回目の signal.generated を pull
        first_messages = pull_messages(subscriber_client, signal_generated_subscription)
        assert len(first_messages) == 1

        # 2回目: 重複検出
        second_response = client.post("/", json=body)
        assert second_response.status_code == 200
        second_data = json.loads(second_response.data)
        assert second_data["status"] == "ok"

        # 2回目の signal.generated は発行されない
        duplicate_messages = pull_messages(
            subscriber_client,
            signal_generated_subscription,
            timeout_seconds=3.0,
        )
        assert len(duplicate_messages) == 0

    def test_idempotency_key_persisted_in_firestore(
        self,
        client: flask.testing.FlaskClient,
        firestore_client: FirestoreClient,
    ) -> None:
        """1回目の処理後に冪等性キーが Firestore に永続化されている。"""
        identifier = "01ARZ3NDEKTSV4RRFFQ69G5FAR"
        cloud_event = build_cloud_event(
            identifier=identifier,
            trace=identifier,
        )
        body = build_pubsub_push_body(cloud_event)

        response = client.post("/", json=body)
        assert response.status_code == 200

        idempotency_key = f"signal-generator:{identifier}"
        document = cast(
            DocumentSnapshot,
            firestore_client.collection("idempotency_keys").document(idempotency_key).get(),
        )
        assert document.exists

    def test_signal_generation_count_remains_one_after_duplicate(
        self,
        client: flask.testing.FlaskClient,
        firestore_client: FirestoreClient,
    ) -> None:
        """重複送信後も signal_runs コレクションのドキュメントは1件のまま。"""
        identifier = "01ARZ3NDEKTSV4RRFFQ69G5FAS"
        cloud_event = build_cloud_event(
            identifier=identifier,
            trace=identifier,
        )
        body = build_pubsub_push_body(cloud_event)

        # 1回目
        client.post("/", json=body)
        # 2回目
        client.post("/", json=body)

        document = cast(
            DocumentSnapshot,
            firestore_client.collection("signal_runs").document(identifier).get(),
        )
        assert document.exists

        # コレクション全体を検索して identifier が重複していないことを確認
        all_documents = list(firestore_client.collection("signal_runs").where("identifier", "==", identifier).stream())
        assert len(all_documents) == 1

    def test_dispatch_count_remains_one_after_duplicate(
        self,
        client: flask.testing.FlaskClient,
        firestore_client: FirestoreClient,
    ) -> None:
        """重複送信後も idempotency_keys コレクションの該当ドキュメントは1件のまま。"""
        identifier = "01ARZ3NDEKTSV4RRFFQ69G5FAT"
        cloud_event = build_cloud_event(
            identifier=identifier,
            trace=identifier,
        )
        body = build_pubsub_push_body(cloud_event)

        # 1回目
        client.post("/", json=body)
        # 2回目
        client.post("/", json=body)

        document = cast(
            DocumentSnapshot,
            firestore_client.collection("idempotency_keys").document(f"signal-generator:{identifier}").get(),
        )
        assert document.exists

        all_documents = list(
            firestore_client.collection("idempotency_keys").where("identifier", "==", identifier).stream()
        )
        assert len(all_documents) == 1

    def test_three_identical_events_produce_exactly_one_output(
        self,
        client: flask.testing.FlaskClient,
        subscriber_client: SubscriberClient,
        signal_generated_subscription: str,
    ) -> None:
        """同一 identifier のイベントを3回送信しても signal.generated は1件のみ。"""
        identifier = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
        cloud_event = build_cloud_event(
            identifier=identifier,
            trace=identifier,
        )
        body = build_pubsub_push_body(cloud_event)

        for _ in range(3):
            response = client.post("/", json=body)
            assert response.status_code == 200

        # 最初の1件分だけ pull できる
        first_messages = pull_messages(subscriber_client, signal_generated_subscription)
        assert len(first_messages) == 1

        # それ以降は何も来ない
        remaining_messages = pull_messages(
            subscriber_client,
            signal_generated_subscription,
            timeout_seconds=3.0,
        )
        assert len(remaining_messages) == 0
