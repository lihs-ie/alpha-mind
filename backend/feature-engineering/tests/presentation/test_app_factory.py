"""Tests for Flask application factory."""

from __future__ import annotations

from unittest.mock import MagicMock

from presentation.app_factory import create_application


class TestCreateApplication:
    """Tests for create_application function."""

    def test_creates_flask_application(self) -> None:
        service = MagicMock()
        application = create_application(service)

        assert application is not None
        assert application.name == "feature-engineering"

    def test_healthz_is_registered(self) -> None:
        service = MagicMock()
        application = create_application(service)

        with application.test_client() as client:
            response = client.get("/healthz")

        assert response.status_code == 200
        assert response.data == b"ok"

    def test_subscriber_endpoint_is_registered(self) -> None:
        service = MagicMock()
        application = create_application(service)

        with application.test_client() as client:
            # Sending empty JSON should trigger decode error (400)
            response = client.post("/", json={}, content_type="application/json")

        assert response.status_code == 400

    def test_service_is_stored_in_config(self) -> None:
        service = MagicMock()
        application = create_application(service)

        assert application.config["FEATURE_GENERATION_SERVICE"] is service
