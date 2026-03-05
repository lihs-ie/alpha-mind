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
    default_universe_count = int(
        os.environ.get("DEFAULT_UNIVERSE_COUNT", str(_DEFAULT_UNIVERSE_COUNT))
    )
    application.config["DEFAULT_UNIVERSE_COUNT"] = default_universe_count

    # サービスの解決
    service = (
        signal_generation_service
        if signal_generation_service is not None
        else _build_signal_generation_service()
    )

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
    signal_topic = os.environ.get("SIGNAL_TOPIC", "signal-events")
    mlflow_tracking_uri = os.environ.get("MLFLOW_TRACKING_URI", "")

    # Firestore リポジトリ
    idempotency_key_repository = FirestoreIdempotencyKeyRepository()
    model_registry_repository = FirestoreModelRegistryRepository()

    # SignalGeneration / SignalDispatch リポジトリ
    # NOTE: 将来的には Firestore 実装を追加。現時点では stub として
    # idempotency_key_repository と model_registry_repository のみ使用。
    signal_generation_repository = _create_stub_repository("signal_generation")
    signal_dispatch_repository = _create_stub_repository("signal_dispatch")

    # ストレージ
    feature_reader = CloudStorageFeatureReader()
    signal_writer = CloudStorageSignalWriter()

    # モデルローダー
    model_loader = MLflowModelLoader(tracking_uri=mlflow_tracking_uri)

    # イベントパブリッシャー
    signal_event_publisher = PubSubSignalEventPublisher(
        project_id=gcp_project,
        topic_id=signal_topic,
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


def _create_stub_repository(name: str) -> object:
    """未実装リポジトリのスタブを返す。

    本番実装が完了するまでの暫定措置。
    """
    logger.warning("Using stub repository for %s", name)

    class _StubRepository:
        def persist(self, *args: object, **kwargs: object) -> None:
            pass

        def find(self, *args: object, **kwargs: object) -> None:
            return None

    return _StubRepository()
