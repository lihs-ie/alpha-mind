"""Tests for dependency injection container."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import flask

from signal_generator.presentation.dependency_container import (
    create_application,
)


def _create_test_application(**kwargs: object) -> flask.Flask:
    """テスト用にモックサービスを注入してアプリケーションを作成する。"""
    if "signal_generation_service" not in kwargs:
        kwargs["signal_generation_service"] = MagicMock()
    return create_application(**kwargs)  # type: ignore[arg-type]


class TestCreateApplication:
    """Flask application factory tests."""

    def test_creates_flask_app(self) -> None:
        application = _create_test_application()
        assert isinstance(application, flask.Flask)

    def test_health_blueprint_registered(self) -> None:
        application = _create_test_application()
        client = application.test_client()
        response = client.get("/healthz")
        assert response.status_code == 200

    def test_subscriber_blueprint_registered(self) -> None:
        application = _create_test_application()
        rules = [rule.rule for rule in application.url_map.iter_rules()]
        assert "/" in rules

    def test_signal_generation_service_in_config(self) -> None:
        application = _create_test_application()
        assert "SIGNAL_GENERATION_SERVICE" in application.config


class TestCreateApplicationWithOverrides:
    """Tests for dependency override capabilities."""

    def test_accepts_service_override(self) -> None:
        mock_service = MagicMock()
        application = create_application(signal_generation_service=mock_service)
        assert application.config["SIGNAL_GENERATION_SERVICE"] is mock_service

    def test_mock_service_is_used_in_subscriber(self) -> None:
        mock_service = MagicMock()
        application = create_application(signal_generation_service=mock_service)
        assert application.config["SIGNAL_GENERATION_SERVICE"] is mock_service


class TestCreateApplicationProduction:
    """Tests for production service build (requires GCP libraries)."""

    def test_without_override_calls_build_service(self) -> None:
        """Verify that without override, _build_signal_generation_service is called."""
        with patch("signal_generator.presentation.dependency_container._build_signal_generation_service") as mock_build:
            mock_build.return_value = MagicMock()
            application = create_application()
            mock_build.assert_called_once()
            assert application.config["SIGNAL_GENERATION_SERVICE"] is mock_build.return_value


class TestBuildSignalGenerationService:
    """Tests for _build_signal_generation_service production wiring."""

    def test_build_service_creates_signal_generation_service(self) -> None:
        """本番依存を全てモックして SignalGenerationService が構築されることを確認。"""
        with (
            patch(
                "signal_generator.infrastructure.firestore.firestore_idempotency_key_repository.FirestoreIdempotencyKeyRepository"
            ),
            patch(
                "signal_generator.infrastructure.firestore.firestore_model_registry_repository.FirestoreModelRegistryRepository"
            ),
            patch(
                "signal_generator.infrastructure.firestore.firestore_signal_generation_repository.FirestoreSignalGenerationRepository"
            ),
            patch(
                "signal_generator.infrastructure.firestore.firestore_signal_dispatch_repository.FirestoreSignalDispatchRepository"
            ),
            patch("signal_generator.infrastructure.storage.cloud_storage_feature_reader.CloudStorageFeatureReader"),
            patch("signal_generator.infrastructure.storage.cloud_storage_signal_writer.CloudStorageSignalWriter"),
            patch("signal_generator.infrastructure.mlflow.mlflow_model_loader.MLflowModelLoader"),
            patch("signal_generator.infrastructure.messaging.pubsub_signal_event_publisher.PubSubSignalEventPublisher"),
            patch("google.cloud.firestore_v1.Client"),
            patch("google.cloud.storage.Client"),
            patch("google.cloud.pubsub_v1.PublisherClient"),
        ):
            from signal_generator.presentation.dependency_container import (
                _build_signal_generation_service,
            )

            service = _build_signal_generation_service()

            from signal_generator.usecase.signal_generation_service import (
                SignalGenerationService,
            )

            assert isinstance(service, SignalGenerationService)


class TestProductionBuildUsesFirestoreRepositories:
    """本番ビルドで Firestore リポジトリが使用されることを確認。"""

    def test_build_service_uses_firestore_signal_generation_repository(self) -> None:
        """_build_signal_generation_service が FirestoreSignalGenerationRepository を使用する。"""
        with (
            patch(
                "signal_generator.infrastructure.firestore.firestore_idempotency_key_repository.FirestoreIdempotencyKeyRepository"
            ),
            patch(
                "signal_generator.infrastructure.firestore.firestore_model_registry_repository.FirestoreModelRegistryRepository"
            ),
            patch(
                "signal_generator.infrastructure.firestore.firestore_signal_generation_repository.FirestoreSignalGenerationRepository"
            ) as mock_signal_generation_repository_class,
            patch(
                "signal_generator.infrastructure.firestore.firestore_signal_dispatch_repository.FirestoreSignalDispatchRepository"
            ) as mock_signal_dispatch_repository_class,
            patch("signal_generator.infrastructure.storage.cloud_storage_feature_reader.CloudStorageFeatureReader"),
            patch("signal_generator.infrastructure.storage.cloud_storage_signal_writer.CloudStorageSignalWriter"),
            patch("signal_generator.infrastructure.mlflow.mlflow_model_loader.MLflowModelLoader"),
            patch("signal_generator.infrastructure.messaging.pubsub_signal_event_publisher.PubSubSignalEventPublisher"),
            patch("google.cloud.firestore_v1.Client"),
            patch("google.cloud.storage.Client"),
            patch("google.cloud.pubsub_v1.PublisherClient"),
        ):
            from signal_generator.presentation.dependency_container import (
                _build_signal_generation_service,
            )

            _build_signal_generation_service()

            mock_signal_generation_repository_class.assert_called_once()
            mock_signal_dispatch_repository_class.assert_called_once()
