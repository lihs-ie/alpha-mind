"""Dependency injection container and Flask application factory.

すべてのインフラストラクチャ依存を解決し、Flask アプリケーションを構築する。
テスト時にはサービスオーバーライドを注入可能。
"""

from __future__ import annotations

import datetime
import logging
import os
from typing import TYPE_CHECKING

import flask

from signal_generator.presentation.health import health_blueprint
from signal_generator.presentation.subscriber import subscriber_blueprint

if TYPE_CHECKING:
    from signal_generator.usecase.signal_generation_service import SignalGenerationService

logger = logging.getLogger(__name__)

_DEFAULT_UNIVERSE_COUNT = 100


def create_application(
    *,
    signal_generation_service: SignalGenerationService | None = None,
) -> flask.Flask:
    """Flask アプリケーションファクトリ。

    Args:
        signal_generation_service: テスト用のサービスオーバーライド。
            None の場合は本番用の依存を解決して構築する。

    Returns:
        構成済みの Flask アプリケーション。
    """
    application = flask.Flask(__name__)

    # 環境変数から設定を読み込む
    default_universe_count = int(os.environ.get("DEFAULT_UNIVERSE_COUNT", str(_DEFAULT_UNIVERSE_COUNT)))
    application.config["DEFAULT_UNIVERSE_COUNT"] = default_universe_count

    # サービスの解決
    service = signal_generation_service if signal_generation_service is not None else _build_signal_generation_service()

    application.config["SIGNAL_GENERATION_SERVICE"] = service

    # Blueprint の登録
    application.register_blueprint(health_blueprint)
    application.register_blueprint(subscriber_blueprint)

    logger.info(
        "Application created: default_universe_count=%d",
        default_universe_count,
    )

    return application


def _build_signal_generation_service() -> SignalGenerationService:
    """本番用の SignalGenerationService を構築する。

    すべてのインフラストラクチャ依存を解決してサービスを返す。
    GCP クライアント等の初期化はここで一度だけ行う。
    """
    from google.cloud.firestore_v1 import Client as FirestoreClient

    from signal_generator.domain.factories.signal_dispatch_factory import (
        SignalDispatchFactory,
    )
    from signal_generator.domain.factories.signal_generation_factory import (
        SignalGenerationFactory,
    )
    from signal_generator.domain.services.approved_model_policy import (
        ApprovedModelPolicy,
    )
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
    from signal_generator.usecase.signal_generation_service import (
        SignalGenerationService,
    )

    # GCP プロジェクト設定
    gcp_project = os.environ.get("GCP_PROJECT", "")
    mlflow_tracking_uri = os.environ.get("MLFLOW_TRACKING_URI", "")

    # Firestore クライアント (全リポジトリで共有)
    firestore_client = FirestoreClient(project=gcp_project)

    # Firestore リポジトリ
    idempotency_key_repository = FirestoreIdempotencyKeyRepository(firestore_client=firestore_client)
    model_registry_repository = FirestoreModelRegistryRepository(firestore_client=firestore_client)
    signal_generation_repository = FirestoreSignalGenerationRepository(firestore_client=firestore_client)
    signal_dispatch_repository = FirestoreSignalDispatchRepository(firestore_client=firestore_client)

    # Cloud Storage クライアント
    from google.cloud.storage import Client as StorageClient

    storage_client = StorageClient(project=gcp_project)

    # ストレージ
    feature_reader = CloudStorageFeatureReader(storage_client=storage_client)
    signal_writer = CloudStorageSignalWriter(storage_client=storage_client)

    # モデルローダー
    model_loader = MLflowModelLoader(tracking_uri=mlflow_tracking_uri)

    # イベントパブリッシャー
    from google.cloud.pubsub_v1 import PublisherClient

    publisher_client = PublisherClient()
    signal_event_publisher = PubSubSignalEventPublisher(
        publisher_client=publisher_client,
        project_id=gcp_project,
    )

    # ドメインサービス・仕様
    signal_generation_factory = SignalGenerationFactory()
    signal_dispatch_factory = SignalDispatchFactory()
    feature_payload_integrity_specification = FeaturePayloadIntegritySpecification()
    approved_model_policy = ApprovedModelPolicy()
    inference_consistency_policy = InferenceConsistencyPolicy()

    return SignalGenerationService(
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
        clock=lambda: datetime.datetime.now(datetime.UTC),
    )
