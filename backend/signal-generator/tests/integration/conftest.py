"""Integration test fixtures using real emulators.

Firestore emulator, Pub/Sub emulator, fake-gcs-server, MLflow server に
接続するクライアントと Flask テストクライアントを提供する。
モックは一切使用しない。

前提条件:
    docker-compose.integration.yml で全エミュレーターが起動済みであること。
"""

from __future__ import annotations

import base64
import contextlib
import datetime
import io
import json
import os
import time
from typing import Any

import flask
import flask.testing
import numpy
import pandas
import pytest
from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore_v1 import Client as FirestoreClient
from google.cloud.pubsub_v1 import PublisherClient, SubscriberClient
from google.cloud.storage import Client as StorageClient

from signal_generator.domain.factories.signal_dispatch_factory import (
    SignalDispatchFactory,
)
from signal_generator.domain.factories.signal_generation_factory import (
    SignalGenerationFactory,
)
from signal_generator.domain.services.approved_model_policy import ApprovedModelPolicy
from signal_generator.domain.services.inference_consistency_policy import (
    InferenceConsistencyPolicy,
)
from signal_generator.domain.specifications.feature_payload_integrity_specification import (
    FeaturePayloadIntegritySpecification,
)
from signal_generator.infrastructure.firestore.firestore_idempotency_key_repository import (
    FirestoreIdempotencyKeyRepository,
)
from signal_generator.infrastructure.firestore.firestore_model_registry_repository import (
    FirestoreModelRegistryRepository,
)
from signal_generator.infrastructure.firestore.firestore_signal_dispatch_repository import (
    FirestoreSignalDispatchRepository,
)
from signal_generator.infrastructure.firestore.firestore_signal_generation_repository import (
    FirestoreSignalGenerationRepository,
)
from signal_generator.infrastructure.messaging.pubsub_signal_event_publisher import (
    PubSubSignalEventPublisher,
)
from signal_generator.infrastructure.mlflow.mlflow_model_loader import (
    MLflowModelLoader,
)
from signal_generator.infrastructure.storage.cloud_storage_feature_reader import (
    CloudStorageFeatureReader,
)
from signal_generator.infrastructure.storage.cloud_storage_signal_writer import (
    CloudStorageSignalWriter,
)
from signal_generator.presentation.dependency_container import create_application
from signal_generator.usecase.signal_audit_writer import SignalAuditWriter
from signal_generator.usecase.signal_generation_service import SignalGenerationService


def pytest_collection_modifyitems(items: list[pytest.Item]) -> None:
    """tests/integration/ 配下の全テストに integration マーカーを自動適用する。"""
    integration_marker = pytest.mark.integration
    for item in items:
        if "/integration/" in str(item.fspath):
            item.add_marker(integration_marker)


# ---------------------------------------------------------------------------
# 環境設定
# ---------------------------------------------------------------------------

PROJECT_ID = os.environ.get("GCP_PROJECT", "alpha-mind-local")
FIRESTORE_EMULATOR_HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8080")
PUBSUB_EMULATOR_HOST = os.environ.get("PUBSUB_EMULATOR_HOST", "localhost:8085")
FAKE_GCS_HOST = os.environ.get("STORAGE_EMULATOR_HOST", "http://localhost:4443")
MLFLOW_TRACKING_URI = os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5050")

# Pub/Sub トピック名
TOPIC_FEATURES_GENERATED = "event-features-generated-v1"
TOPIC_SIGNAL_GENERATED = "event-signal-generated-v1"
TOPIC_SIGNAL_GENERATION_FAILED = "event-signal-generation-failed-v1"

# テスト用 GCS バケット・パス
TEST_FEATURE_BUCKET = "alpha-mind-local"
TEST_FEATURE_OBJECT_PATH = "features/feature-v1.parquet"
TEST_FEATURE_STORAGE_PATH = f"gs://{TEST_FEATURE_BUCKET}/{TEST_FEATURE_OBJECT_PATH}"
TEST_SIGNAL_BUCKET = "signal-store"

# テスト用モデル情報
TEST_MODEL_VERSION = "signal-model-v1"

# Firestore コレクション名
FIRESTORE_COLLECTIONS = [
    "idempotency_keys",
    "model_registry",
    "signal_runs",
]


# ---------------------------------------------------------------------------
# Emulator 環境変数を設定
# ---------------------------------------------------------------------------


def _configure_emulator_environment() -> None:
    """エミュレーター接続用の環境変数を設定する。"""
    os.environ["FIRESTORE_EMULATOR_HOST"] = FIRESTORE_EMULATOR_HOST
    os.environ["PUBSUB_EMULATOR_HOST"] = PUBSUB_EMULATOR_HOST
    os.environ["STORAGE_EMULATOR_HOST"] = FAKE_GCS_HOST
    os.environ["GCP_PROJECT"] = PROJECT_ID
    os.environ["MLFLOW_TRACKING_URI"] = MLFLOW_TRACKING_URI


_configure_emulator_environment()


# ---------------------------------------------------------------------------
# Firestore fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="session")
def firestore_client() -> FirestoreClient:
    """Firestore エミュレーターに接続するクライアント。"""
    return FirestoreClient(project=PROJECT_ID)


@pytest.fixture(autouse=True)
def _clean_firestore(firestore_client: FirestoreClient) -> None:
    """各テスト前に Firestore の全コレクションをクリアする。"""
    for collection_name in FIRESTORE_COLLECTIONS:
        _delete_collection(firestore_client, collection_name)


def _delete_collection(client: FirestoreClient, collection_name: str) -> None:
    """Firestore コレクションの全ドキュメントを削除する。"""
    collection_reference = client.collection(collection_name)
    documents = list(collection_reference.limit(500).stream())
    for document in documents:
        document.reference.delete()


# ---------------------------------------------------------------------------
# Pub/Sub fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="session")
def publisher_client() -> PublisherClient:
    """Pub/Sub エミュレーターに接続する PublisherClient。"""
    return PublisherClient()


@pytest.fixture(scope="session")
def subscriber_client() -> SubscriberClient:
    """Pub/Sub エミュレーターに接続する SubscriberClient。"""
    return SubscriberClient()


@pytest.fixture(scope="session")
def _ensure_pubsub_topics(publisher_client: PublisherClient) -> None:
    """テストに必要な Pub/Sub トピックを作成する (存在しない場合のみ)。"""
    topics = [
        TOPIC_FEATURES_GENERATED,
        TOPIC_SIGNAL_GENERATED,
        TOPIC_SIGNAL_GENERATION_FAILED,
    ]
    for topic_name in topics:
        topic_path = publisher_client.topic_path(PROJECT_ID, topic_name)
        with contextlib.suppress(AlreadyExists):
            publisher_client.create_topic(request={"name": topic_path})


@pytest.fixture(scope="session")
def signal_generated_subscription(
    subscriber_client: SubscriberClient,
    publisher_client: PublisherClient,
    _ensure_pubsub_topics: None,
) -> str:
    """signal.generated トピックの pull サブスクリプションを作成して名前を返す。"""
    subscription_name = f"projects/{PROJECT_ID}/subscriptions/integration-test-signal-generated"
    topic_path = publisher_client.topic_path(PROJECT_ID, TOPIC_SIGNAL_GENERATED)
    with contextlib.suppress(AlreadyExists):
        subscriber_client.create_subscription(
            request={
                "name": subscription_name,
                "topic": topic_path,
                "ack_deadline_seconds": 60,
            }
        )
    return subscription_name


@pytest.fixture(scope="session")
def signal_failed_subscription(
    subscriber_client: SubscriberClient,
    publisher_client: PublisherClient,
    _ensure_pubsub_topics: None,
) -> str:
    """signal.generation.failed トピックの pull サブスクリプションを作成して名前を返す。"""
    subscription_name = f"projects/{PROJECT_ID}/subscriptions/integration-test-signal-failed"
    topic_path = publisher_client.topic_path(PROJECT_ID, TOPIC_SIGNAL_GENERATION_FAILED)
    with contextlib.suppress(AlreadyExists):
        subscriber_client.create_subscription(
            request={
                "name": subscription_name,
                "topic": topic_path,
                "ack_deadline_seconds": 60,
            }
        )
    return subscription_name


def pull_messages(
    subscriber_client: SubscriberClient,
    subscription_name: str,
    max_messages: int = 10,
    timeout_seconds: float = 10.0,
) -> list[dict[str, Any]]:
    """サブスクリプションからメッセージを pull してデコードして返す。

    指定された timeout_seconds の間、メッセージが届くまでポーリングする。
    """
    deadline = time.monotonic() + timeout_seconds
    decoded_messages: list[dict[str, Any]] = []

    while time.monotonic() < deadline:
        response = subscriber_client.pull(
            request={
                "subscription": subscription_name,
                "max_messages": max_messages,
            },
            timeout=min(5.0, deadline - time.monotonic() + 0.1),
        )
        if response.received_messages:
            acknowledge_identifiers = []
            for received_message in response.received_messages:
                data = json.loads(received_message.message.data.decode("utf-8"))
                decoded_messages.append(data)
                acknowledge_identifiers.append(received_message.ack_id)
            subscriber_client.acknowledge(
                request={
                    "subscription": subscription_name,
                    "ack_ids": acknowledge_identifiers,
                }
            )
            return decoded_messages
        time.sleep(0.5)

    return decoded_messages


def drain_subscription(
    subscriber_client: SubscriberClient,
    subscription_name: str,
) -> None:
    """サブスクリプションの未処理メッセージをすべて ack して排出する。"""
    try:
        response = subscriber_client.pull(
            request={
                "subscription": subscription_name,
                "max_messages": 100,
            },
            timeout=3.0,
        )
        if response.received_messages:
            acknowledge_identifiers = [message.ack_id for message in response.received_messages]
            subscriber_client.acknowledge(
                request={
                    "subscription": subscription_name,
                    "ack_ids": acknowledge_identifiers,
                }
            )
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Cloud Storage (fake-gcs-server) fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="session")
def storage_client() -> StorageClient:
    """fake-gcs-server に接続する StorageClient。"""
    from google.auth.credentials import AnonymousCredentials

    return StorageClient(
        project=PROJECT_ID,
        credentials=AnonymousCredentials(),
    )


@pytest.fixture(scope="session")
def _ensure_gcs_buckets(storage_client: StorageClient) -> None:
    """テストに必要な GCS バケットを作成する。"""
    for bucket_name in [TEST_FEATURE_BUCKET, TEST_SIGNAL_BUCKET]:
        with contextlib.suppress(Exception):
            storage_client.create_bucket(bucket_name)


@pytest.fixture(autouse=True)
def _upload_test_feature_parquet(
    storage_client: StorageClient,
    _ensure_gcs_buckets: None,
) -> None:
    """テスト用の特徴量 Parquet ファイルを GCS にアップロードする。"""
    feature_dataframe = _build_test_feature_dataframe()
    buffer = io.BytesIO()
    feature_dataframe.to_parquet(buffer, index=False)
    buffer.seek(0)

    bucket = storage_client.bucket(TEST_FEATURE_BUCKET)
    blob = bucket.blob(TEST_FEATURE_OBJECT_PATH)
    blob.upload_from_file(buffer, content_type="application/octet-stream")


def _build_test_feature_dataframe(row_count: int = 100) -> pandas.DataFrame:
    """テスト用の特徴量 DataFrame を構築する。

    LightGBM は数値カラムのみ受け付けるため、文字列カラムは含めない。
    学習時と同じカラム構成 (feature_1, feature_2, feature_3) にする。
    """
    numpy.random.seed(42)
    return pandas.DataFrame(
        {
            "feature_1": numpy.random.randn(row_count),
            "feature_2": numpy.random.randn(row_count),
            "feature_3": numpy.random.randn(row_count),
        }
    )


# ---------------------------------------------------------------------------
# MLflow fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="session")
def _register_test_model() -> None:
    """MLflow にテスト用モデルを登録する。

    LightGBM のダミーモデルを学習してMLflow に記録・登録する。
    lightgbm / mlflow はランタイム依存のためフィクスチャ内で遅延インポートする。
    """
    import lightgbm
    import mlflow

    mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)

    # ダミーデータで LightGBM モデルを学習
    numpy.random.seed(42)
    feature_count = 3
    sample_count = 100
    training_features = numpy.random.randn(sample_count, feature_count)
    training_labels = numpy.random.randn(sample_count)

    model = lightgbm.LGBMRegressor(n_estimators=5, verbose=-1)
    model.fit(training_features, training_labels)

    # MLflow に記録
    with mlflow.start_run(run_name="integration-test-model"):
        mlflow.lightgbm.log_model(
            model,
            artifact_path="model",
            registered_model_name=TEST_MODEL_VERSION,
        )


# ---------------------------------------------------------------------------
# Firestore テストデータ投入
# ---------------------------------------------------------------------------


def seed_approved_model(firestore_client: FirestoreClient) -> None:
    """Firestore の model_registry に approved モデルを登録する。"""
    document_reference = firestore_client.collection("model_registry").document(TEST_MODEL_VERSION)
    document_reference.set(
        {
            "modelVersion": TEST_MODEL_VERSION,
            "status": "approved",
            "createdAt": datetime.datetime.now(datetime.UTC),
            "decidedAt": datetime.datetime.now(datetime.UTC),
        }
    )


# ---------------------------------------------------------------------------
# Flask application / client fixtures
# ---------------------------------------------------------------------------


@pytest.fixture()
def application(
    firestore_client: FirestoreClient,
    publisher_client: PublisherClient,
    storage_client: StorageClient,
    _ensure_pubsub_topics: None,
    _ensure_gcs_buckets: None,
    _register_test_model: None,
) -> flask.Flask:
    """統合テスト用の Flask アプリケーション。

    全依存を実エミュレーターのクライアントで構築する。
    """
    # リポジトリ
    idempotency_key_repository = FirestoreIdempotencyKeyRepository(
        firestore_client=firestore_client,
    )
    model_registry_repository = FirestoreModelRegistryRepository(
        firestore_client=firestore_client,
    )
    signal_generation_repository = FirestoreSignalGenerationRepository(
        firestore_client=firestore_client,
    )
    signal_dispatch_repository = FirestoreSignalDispatchRepository(
        firestore_client=firestore_client,
    )

    # ストレージ
    feature_reader = CloudStorageFeatureReader(storage_client=storage_client)
    signal_writer = CloudStorageSignalWriter(storage_client=storage_client)

    # モデルローダー
    model_loader = MLflowModelLoader(tracking_uri=MLFLOW_TRACKING_URI)

    # イベントパブリッシャー
    signal_event_publisher = PubSubSignalEventPublisher(
        publisher_client=publisher_client,
        project_id=PROJECT_ID,
    )

    # ドメインサービス・仕様
    signal_generation_factory = SignalGenerationFactory()
    signal_dispatch_factory = SignalDispatchFactory()
    feature_payload_integrity_specification = FeaturePayloadIntegritySpecification()
    approved_model_policy = ApprovedModelPolicy()
    inference_consistency_policy = InferenceConsistencyPolicy()
    signal_audit_writer = SignalAuditWriter()

    service = SignalGenerationService(
        idempotency_key_repository=idempotency_key_repository,
        model_registry_repository=model_registry_repository,
        signal_generation_repository=signal_generation_repository,
        signal_dispatch_repository=signal_dispatch_repository,
        feature_reader=feature_reader,
        model_loader=model_loader,
        signal_writer=signal_writer,
        signal_event_publisher=signal_event_publisher,
        signal_generation_factory=signal_generation_factory,
        signal_dispatch_factory=signal_dispatch_factory,
        feature_payload_integrity_specification=feature_payload_integrity_specification,
        approved_model_policy=approved_model_policy,
        inference_consistency_policy=inference_consistency_policy,
        signal_audit_writer=signal_audit_writer,
        clock=lambda: datetime.datetime.now(datetime.UTC),
    )

    return create_application(signal_generation_service=service)


@pytest.fixture()
def client(application: flask.Flask) -> flask.testing.FlaskClient:
    """Flask テストクライアント。"""
    return application.test_client()


# ---------------------------------------------------------------------------
# Pub/Sub push メッセージ構築ヘルパー
# ---------------------------------------------------------------------------


def build_cloud_event(
    *,
    identifier: str = "01ARZ3NDEKTSV4RRFFQ69G5FAC",
    event_type: str = "features.generated",
    occurred_at: str = "2026-03-05T00:20:00Z",
    trace: str = "01ARZ3NDEKTSV4RRFFQ69G5FAC",
    schema_version: str = "1.0.0",
    payload: dict[str, object] | None = None,
) -> dict[str, object]:
    """CloudEvents エンベロープを構築する。"""
    if payload is None:
        payload = {
            "targetDate": "2026-03-05",
            "featureVersion": "feature-v1",
            "storagePath": TEST_FEATURE_STORAGE_PATH,
            "universeCount": 100,
        }
    return {
        "identifier": identifier,
        "eventType": event_type,
        "occurredAt": occurred_at,
        "trace": trace,
        "schemaVersion": schema_version,
        "payload": payload,
    }


def build_pubsub_push_body(cloud_event: dict[str, object]) -> dict[str, object]:
    """Pub/Sub push 形式のリクエストボディを構築する。"""
    encoded_data = base64.b64encode(json.dumps(cloud_event).encode()).decode()
    return {
        "message": {
            "data": encoded_data,
            "messageId": "integration-test-msg-001",
            "publishTime": "2026-03-05T00:20:00Z",
        },
        "subscription": f"projects/{PROJECT_ID}/subscriptions/signal-generator-sub",
    }
