"""Tests for health check endpoint."""

from __future__ import annotations

import json

import flask
import pytest

from signal_generator.presentation.health import health_blueprint


@pytest.fixture()
def application() -> flask.Flask:
    """Create a Flask test app with the health blueprint."""
    application = flask.Flask(__name__)
    application.register_blueprint(health_blueprint)
    application.config["TESTING"] = True
    return application


@pytest.fixture()
def client(application: flask.Flask) -> flask.testing.FlaskClient:
    """Create a Flask test client."""
    return application.test_client()


class TestHealthCheck:
    """GET /healthz endpoint tests."""

    def test_returns_200_ok(self, client: flask.testing.FlaskClient) -> None:
        response = client.get("/healthz")
        assert response.status_code == 200

    def test_returns_json_content_type(self, client: flask.testing.FlaskClient) -> None:
        response = client.get("/healthz")
        assert response.content_type == "application/json"

    def test_returns_status_ok(self, client: flask.testing.FlaskClient) -> None:
        response = client.get("/healthz")
        data = json.loads(response.data)
        assert data["status"] == "ok"

    def test_returns_service_name(self, client: flask.testing.FlaskClient) -> None:
        response = client.get("/healthz")
        data = json.loads(response.data)
        assert data["service"] == "signal-generator"
