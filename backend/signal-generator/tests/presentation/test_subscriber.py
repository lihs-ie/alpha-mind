"""Tests for Pub/Sub subscriber endpoint."""

from __future__ import annotations

import base64
import json
from datetime import date
from unittest.mock import MagicMock

import flask
import pytest

from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.presentation.subscriber import subscriber_blueprint
from signal_generator.usecase.generate_signal_command import GenerateSignalCommand
from signal_generator.usecase.generate_signal_result import GenerateSignalResult


def _build_cloud_event(
    *,
    identifier: str = "01JARQ0000AAAAAAAAAAAAAAAA",
    event_type: str = "features.generated",
    occurred_at: str = "2026-03-05T09:00:00Z",
    trace: str = "01JARQ0000BBBBBBBBBBBBBBBB",
    schema_version: str = "1.0.0",
    payload: dict[str, object] | None = None,
) -> dict[str, object]:
    if payload is None:
        payload = {
            "targetDate": "2026-03-05",
            "featureVersion": "v1.0.0",
            "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
        }
    return {
        "identifier": identifier,
        "eventType": event_type,
        "occurredAt": occurred_at,
        "trace": trace,
        "schemaVersion": schema_version,
        "payload": payload,
    }


def _build_pubsub_body(cloud_event: dict[str, object]) -> dict[str, object]:
    encoded = base64.b64encode(json.dumps(cloud_event).encode()).decode()
    return {
        "message": {
            "data": encoded,
            "messageId": "msg-001",
            "publishTime": "2026-03-05T09:00:00Z",
        },
        "subscription": "projects/test/subscriptions/signal-generator-sub",
    }


@pytest.fixture()
def mock_service() -> MagicMock:
    return MagicMock()


@pytest.fixture()
def application(mock_service: MagicMock) -> flask.Flask:
    application = flask.Flask(__name__)
    application.config["TESTING"] = True
    application.config["SIGNAL_GENERATION_SERVICE"] = mock_service
    application.config["DEFAULT_UNIVERSE_COUNT"] = 100
    application.register_blueprint(subscriber_blueprint)
    return application


@pytest.fixture()
def client(application: flask.Flask) -> flask.testing.FlaskClient:
    return application.test_client()


class TestSubscriberSuccess:
    """POST / with valid message and successful usecase."""

    def test_returns_200_on_success(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        mock_service.execute.return_value = GenerateSignalResult.success()
        cloud_event = _build_cloud_event()
        body = _build_pubsub_body(cloud_event)

        response = client.post("/", json=body)

        assert response.status_code == 200

    def test_calls_service_with_correct_command(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        mock_service.execute.return_value = GenerateSignalResult.success()
        cloud_event = _build_cloud_event()
        body = _build_pubsub_body(cloud_event)

        client.post("/", json=body)

        mock_service.execute.assert_called_once()
        command = mock_service.execute.call_args[0][0]
        assert isinstance(command, GenerateSignalCommand)
        assert command.identifier == "01JARQ0000AAAAAAAAAAAAAAAA"
        assert command.target_date == date(2026, 3, 5)
        assert command.feature_version == "v1.0.0"
        assert command.storage_path == "gs://features/2026-03-05/v1.0.0.parquet"
        assert command.trace == "01JARQ0000BBBBBBBBBBBBBBBB"

    def test_uses_default_universe_count_when_not_in_payload(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        mock_service.execute.return_value = GenerateSignalResult.success()
        cloud_event = _build_cloud_event()
        body = _build_pubsub_body(cloud_event)

        client.post("/", json=body)

        command = mock_service.execute.call_args[0][0]
        assert command.universe_count == 100  # DEFAULT_UNIVERSE_COUNT

    def test_uses_payload_universe_count_when_present(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        mock_service.execute.return_value = GenerateSignalResult.success()
        payload = {
            "targetDate": "2026-03-05",
            "featureVersion": "v1.0.0",
            "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
            "universeCount": 500,
        }
        cloud_event = _build_cloud_event(payload=payload)
        body = _build_pubsub_body(cloud_event)

        client.post("/", json=body)

        command = mock_service.execute.call_args[0][0]
        assert command.universe_count == 500

    def test_returns_200_on_duplicate(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        mock_service.execute.return_value = GenerateSignalResult.duplicate()
        cloud_event = _build_cloud_event()
        body = _build_pubsub_body(cloud_event)

        response = client.post("/", json=body)

        assert response.status_code == 200


class TestSubscriberValidationFailure:
    """POST / with invalid messages - should return 200 (ack, non-retryable)."""

    def test_returns_200_on_invalid_event_type(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        cloud_event = _build_cloud_event(event_type="data.collected")
        body = _build_pubsub_body(cloud_event)

        response = client.post("/", json=body)

        assert response.status_code == 200
        mock_service.execute.assert_not_called()

    def test_returns_200_on_missing_fields(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        cloud_event = _build_cloud_event()
        del cloud_event["identifier"]
        body = _build_pubsub_body(cloud_event)

        response = client.post("/", json=body)

        assert response.status_code == 200
        mock_service.execute.assert_not_called()

    def test_returns_200_on_empty_body(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        response = client.post("/", json={})

        assert response.status_code == 200
        mock_service.execute.assert_not_called()

    def test_returns_200_on_non_json_body(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        response = client.post("/", data=b"not json", content_type="text/plain")

        assert response.status_code == 200
        mock_service.execute.assert_not_called()

    def test_returns_200_on_command_validation_failure(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        """GenerateSignalCommand の __post_init__ バリデーション失敗は 200 で ack。"""
        payload: dict[str, object] = {
            "targetDate": "2026-03-05",
            "featureVersion": "v1.0.0",
            "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
            "universeCount": -1,
        }
        cloud_event = _build_cloud_event(payload=payload)
        body = _build_pubsub_body(cloud_event)

        response = client.post("/", json=body)

        assert response.status_code == 200
        mock_service.execute.assert_not_called()


class TestSubscriberUsecaseFailure:
    """POST / when usecase returns failure."""

    def test_returns_500_on_retryable_failure(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        mock_service.execute.return_value = GenerateSignalResult.failure(
            reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
            detail="Firestore unavailable",
        )
        cloud_event = _build_cloud_event()
        body = _build_pubsub_body(cloud_event)

        response = client.post("/", json=body)

        assert response.status_code == 500

    def test_returns_200_on_non_retryable_failure(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        mock_service.execute.return_value = GenerateSignalResult.failure(
            reason_code=ReasonCode.MODEL_NOT_APPROVED,
            detail="No approved model found",
        )
        cloud_event = _build_cloud_event()
        body = _build_pubsub_body(cloud_event)

        response = client.post("/", json=body)

        assert response.status_code == 200

    def test_returns_500_on_unhandled_exception(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        mock_service.execute.side_effect = RuntimeError("unexpected")
        cloud_event = _build_cloud_event()
        body = _build_pubsub_body(cloud_event)

        response = client.post("/", json=body)

        assert response.status_code == 500


class TestSubscriberResponseBody:
    """Response body format validation."""

    def test_success_response_contains_status(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        mock_service.execute.return_value = GenerateSignalResult.success()
        cloud_event = _build_cloud_event()
        body = _build_pubsub_body(cloud_event)

        response = client.post("/", json=body)
        data = json.loads(response.data)

        assert data["status"] == "ok"

    def test_validation_error_response_contains_error(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        cloud_event = _build_cloud_event(event_type="wrong.type")
        body = _build_pubsub_body(cloud_event)

        response = client.post("/", json=body)
        data = json.loads(response.data)

        assert "error" in data

    def test_retryable_failure_response_contains_error(
        self, client: flask.testing.FlaskClient, mock_service: MagicMock
    ) -> None:
        mock_service.execute.return_value = GenerateSignalResult.failure(
            reason_code=ReasonCode.DEPENDENCY_TIMEOUT,
        )
        cloud_event = _build_cloud_event()
        body = _build_pubsub_body(cloud_event)

        response = client.post("/", json=body)
        data = json.loads(response.data)

        assert "error" in data
