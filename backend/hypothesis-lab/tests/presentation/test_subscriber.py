"""Tests for Pub/Sub subscriber Blueprint for hypothesis-lab service."""

from __future__ import annotations

import base64
import json
from typing import Any
from unittest.mock import MagicMock

import flask
import pytest

from application.hypothesis_workflow_service import HypothesisProcessingError, RetryableHypothesisError
from domain.value_object.enums import ReasonCode
from presentation.subscriber import subscriber_blueprint


@pytest.fixture()
def mock_hypothesis_workflow_service() -> MagicMock:
    return MagicMock()


@pytest.fixture()
def application(mock_hypothesis_workflow_service: MagicMock) -> flask.Flask:
    application = flask.Flask(__name__)
    application.config["TESTING"] = True
    application.config["HYPOTHESIS_WORKFLOW_SERVICE"] = mock_hypothesis_workflow_service
    application.register_blueprint(subscriber_blueprint)
    return application


def _make_pubsub_body(event_type: str = "hypothesis.proposed") -> dict[str, Any]:
    cloud_event: dict[str, Any] = {
        "identifier": "01JQXK5V6R3YBNM7GTWP0HS4EA",
        "eventType": event_type,
        "occurredAt": "2026-03-05T09:00:00Z",
        "trace": "01JQXK5V6R3YBNM7GTWP0HS4EB",
        "schemaVersion": "1.0",
        "payload": {"title": "Test hypothesis", "symbol": "7203"},
    }
    encoded = base64.b64encode(json.dumps(cloud_event).encode("utf-8")).decode("utf-8")
    return {
        "message": {
            "data": encoded,
            "messageId": "msg-123",
            "publishTime": "2026-03-05T09:00:00Z",
        },
        "subscription": "projects/test/subscriptions/test-sub",
    }


class TestHandleHypothesisProposed:
    """Tests for POST /pubsub/proposed endpoint."""

    def test_valid_message_returns_204(
        self,
        application: flask.Flask,
        mock_hypothesis_workflow_service: MagicMock,
    ) -> None:
        with application.test_client() as client:
            response = client.post(
                "/pubsub/proposed",
                json=_make_pubsub_body("hypothesis.proposed"),
                content_type="application/json",
            )

        assert response.status_code == 204
        mock_hypothesis_workflow_service.process_proposed.assert_called_once()

    def test_decode_error_returns_400(
        self,
        application: flask.Flask,
        mock_hypothesis_workflow_service: MagicMock,
    ) -> None:
        with application.test_client() as client:
            response = client.post(
                "/pubsub/proposed",
                json={},
                content_type="application/json",
            )

        assert response.status_code == 400
        mock_hypothesis_workflow_service.process_proposed.assert_not_called()

    def test_non_json_body_returns_400(
        self,
        application: flask.Flask,
    ) -> None:
        with application.test_client() as client:
            response = client.post(
                "/pubsub/proposed",
                data="not json",
                content_type="text/plain",
            )

        assert response.status_code == 400

    def test_retryable_processing_error_returns_500(
        self,
        application: flask.Flask,
        mock_hypothesis_workflow_service: MagicMock,
    ) -> None:
        mock_hypothesis_workflow_service.process_proposed.side_effect = RetryableHypothesisError(
            status=503,
            title="Service Unavailable",
            detail="Transient failure",
            reason_code=ReasonCode.STATE_CONFLICT,
            trace="01JQXK5V6R3YBNM7GTWP0HS4EB",
            retryable=True,
        )

        with application.test_client() as client:
            response = client.post(
                "/pubsub/proposed",
                json=_make_pubsub_body("hypothesis.proposed"),
                content_type="application/json",
            )

        assert response.status_code == 500

    def test_non_retryable_processing_error_returns_400(
        self,
        application: flask.Flask,
        mock_hypothesis_workflow_service: MagicMock,
    ) -> None:
        mock_hypothesis_workflow_service.process_proposed.side_effect = HypothesisProcessingError(
            status=400,
            title="Bad Request",
            detail="Invalid payload",
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            trace="01JQXK5V6R3YBNM7GTWP0HS4EB",
            retryable=False,
        )

        with application.test_client() as client:
            response = client.post(
                "/pubsub/proposed",
                json=_make_pubsub_body("hypothesis.proposed"),
                content_type="application/json",
            )

        assert response.status_code == 400

    def test_unexpected_error_returns_500(
        self,
        application: flask.Flask,
        mock_hypothesis_workflow_service: MagicMock,
    ) -> None:
        mock_hypothesis_workflow_service.process_proposed.side_effect = RuntimeError("unexpected")

        with application.test_client() as client:
            response = client.post(
                "/pubsub/proposed",
                json=_make_pubsub_body("hypothesis.proposed"),
                content_type="application/json",
            )

        assert response.status_code == 500


class TestHandleHypothesisDemoCompleted:
    """Tests for POST /pubsub/demo-completed endpoint."""

    def test_valid_message_returns_204(
        self,
        application: flask.Flask,
        mock_hypothesis_workflow_service: MagicMock,
    ) -> None:
        with application.test_client() as client:
            response = client.post(
                "/pubsub/demo-completed",
                json=_make_pubsub_body("hypothesis.demo.completed"),
                content_type="application/json",
            )

        assert response.status_code == 204
        mock_hypothesis_workflow_service.process_demo_completed.assert_called_once()

    def test_decode_error_returns_400(
        self,
        application: flask.Flask,
        mock_hypothesis_workflow_service: MagicMock,
    ) -> None:
        with application.test_client() as client:
            response = client.post(
                "/pubsub/demo-completed",
                json={},
                content_type="application/json",
            )

        assert response.status_code == 400
        mock_hypothesis_workflow_service.process_demo_completed.assert_not_called()

    def test_non_json_body_returns_400(
        self,
        application: flask.Flask,
    ) -> None:
        with application.test_client() as client:
            response = client.post(
                "/pubsub/demo-completed",
                data="not json",
                content_type="text/plain",
            )

        assert response.status_code == 400

    def test_retryable_processing_error_returns_500(
        self,
        application: flask.Flask,
        mock_hypothesis_workflow_service: MagicMock,
    ) -> None:
        mock_hypothesis_workflow_service.process_demo_completed.side_effect = RetryableHypothesisError(
            status=503,
            title="Service Unavailable",
            detail="Transient failure",
            reason_code=ReasonCode.STATE_CONFLICT,
            trace="01JQXK5V6R3YBNM7GTWP0HS4EB",
            retryable=True,
        )

        with application.test_client() as client:
            response = client.post(
                "/pubsub/demo-completed",
                json=_make_pubsub_body("hypothesis.demo.completed"),
                content_type="application/json",
            )

        assert response.status_code == 500

    def test_unexpected_error_returns_500(
        self,
        application: flask.Flask,
        mock_hypothesis_workflow_service: MagicMock,
    ) -> None:
        mock_hypothesis_workflow_service.process_demo_completed.side_effect = RuntimeError("unexpected")

        with application.test_client() as client:
            response = client.post(
                "/pubsub/demo-completed",
                json=_make_pubsub_body("hypothesis.demo.completed"),
                content_type="application/json",
            )

        assert response.status_code == 500
