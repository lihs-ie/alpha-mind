"""Tests for health check Blueprint."""

from __future__ import annotations

import flask
import pytest

from presentation.health import health_blueprint


@pytest.fixture()
def application() -> flask.Flask:
    application = flask.Flask(__name__)
    application.register_blueprint(health_blueprint)
    application.config["TESTING"] = True
    return application


class TestHealthBlueprint:
    """Tests for health check endpoint."""

    def test_healthz_returns_200_with_json_body(self, application: flask.Flask) -> None:
        with application.test_client() as client:
            response = client.get("/healthz")

        assert response.status_code == 200
        assert response.content_type == "application/json"
        data = response.get_json()
        assert data["status"] == "ok"
        assert "time" in data

    def test_healthz_time_is_iso8601_utc(self, application: flask.Flask) -> None:
        with application.test_client() as client:
            response = client.get("/healthz")

        data = response.get_json()
        assert data["time"].endswith("Z")

    def test_unknown_path_returns_404(self, application: flask.Flask) -> None:
        with application.test_client() as client:
            response = client.get("/unknown")

        assert response.status_code == 404
