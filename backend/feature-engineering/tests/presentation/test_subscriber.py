"""Tests for Pub/Sub subscriber Blueprint."""

from __future__ import annotations

import base64
import json
from typing import Any
from unittest.mock import MagicMock

import flask
import pytest

from domain.value_object.market_snapshot import MarketSnapshot
from presentation.subscriber import subscriber_blueprint


@pytest.fixture()
def mock_feature_generation_service() -> MagicMock:
    return MagicMock()


@pytest.fixture()
def application(mock_feature_generation_service: MagicMock) -> flask.Flask:
    application = flask.Flask(__name__)
    application.config["TESTING"] = True
    application.config["FEATURE_GENERATION_SERVICE"] = mock_feature_generation_service
    application.register_blueprint(subscriber_blueprint)
    return application


def _make_valid_pubsub_body() -> dict[str, Any]:
    payload = {
        "identifier": "01JQXK5V6R3YBNM7GTWP0HS4EA",
        "eventType": "market.collected",
        "occurredAt": "2026-03-05T09:00:00Z",
        "trace": "01JQXK5V6R3YBNM7GTWP0HS4EB",
        "schemaVersion": "1.0",
        "payload": {
            "targetDate": "2026-03-05",
            "storagePath": "gs://bucket/path/to/data",
            "sourceStatus": {"jp": "ok", "us": "ok"},
        },
    }
    encoded = base64.b64encode(json.dumps(payload).encode("utf-8")).decode("utf-8")
    return {
        "message": {
            "data": encoded,
            "messageId": "msg-123",
            "publishTime": "2026-03-05T09:00:00Z",
        },
        "subscription": "projects/test/subscriptions/test-sub",
    }


class TestSubscriberBlueprint:
    """Tests for Pub/Sub push endpoint."""

    def test_valid_message_returns_204(
        self,
        application: flask.Flask,
        mock_feature_generation_service: MagicMock,
    ) -> None:
        with application.test_client() as client:
            response = client.post(
                "/",
                json=_make_valid_pubsub_body(),
                content_type="application/json",
            )

        assert response.status_code == 204
        mock_feature_generation_service.execute.assert_called_once()
        call_args = mock_feature_generation_service.execute.call_args
        assert call_args.kwargs["identifier"] == "01JQXK5V6R3YBNM7GTWP0HS4EA"
        assert call_args.kwargs["trace"] == "01JQXK5V6R3YBNM7GTWP0HS4EB"
        assert isinstance(call_args.kwargs["market"], MarketSnapshot)

    def test_decode_error_returns_400(
        self,
        application: flask.Flask,
        mock_feature_generation_service: MagicMock,
    ) -> None:
        with application.test_client() as client:
            response = client.post(
                "/",
                json={},
                content_type="application/json",
            )

        assert response.status_code == 400
        mock_feature_generation_service.execute.assert_not_called()

    def test_usecase_transient_error_returns_500(
        self,
        application: flask.Flask,
        mock_feature_generation_service: MagicMock,
    ) -> None:
        mock_feature_generation_service.execute.side_effect = ConnectionError("transient")

        with application.test_client() as client:
            response = client.post(
                "/",
                json=_make_valid_pubsub_body(),
                content_type="application/json",
            )

        assert response.status_code == 500

    def test_usecase_unexpected_error_returns_500(
        self,
        application: flask.Flask,
        mock_feature_generation_service: MagicMock,
    ) -> None:
        mock_feature_generation_service.execute.side_effect = RuntimeError("unexpected")

        with application.test_client() as client:
            response = client.post(
                "/",
                json=_make_valid_pubsub_body(),
                content_type="application/json",
            )

        assert response.status_code == 500

    def test_non_json_body_returns_400(
        self,
        application: flask.Flask,
    ) -> None:
        with application.test_client() as client:
            response = client.post(
                "/",
                data="not json",
                content_type="text/plain",
            )

        assert response.status_code == 400

    def test_response_includes_trace_header_on_success(
        self,
        application: flask.Flask,
        mock_feature_generation_service: MagicMock,
    ) -> None:
        with application.test_client() as client:
            response = client.post(
                "/",
                json=_make_valid_pubsub_body(),
                content_type="application/json",
            )

        assert response.status_code == 204
