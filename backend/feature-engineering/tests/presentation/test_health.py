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

    def test_healthz_returns_200_ok(self, application: flask.Flask) -> None:
        with application.test_client() as client:
            response = client.get("/healthz")

        assert response.status_code == 200
        assert response.data == b"ok"
        assert "text/plain" in response.content_type

    def test_unknown_path_returns_404(self, application: flask.Flask) -> None:
        with application.test_client() as client:
            response = client.get("/unknown")

        assert response.status_code == 404
