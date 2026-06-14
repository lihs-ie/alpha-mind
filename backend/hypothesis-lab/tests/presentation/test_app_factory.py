"""Tests for Flask application factory for hypothesis-lab service."""

from __future__ import annotations

from unittest.mock import MagicMock

from presentation.app_factory import create_application


class TestCreateApplication:
    """Tests for create_application function."""

    def test_creates_flask_application(self) -> None:
        service = MagicMock()
        application = create_application(service)

        assert application is not None
        assert application.name == "hypothesis-lab"

    def test_healthz_is_registered(self) -> None:
        service = MagicMock()
        application = create_application(service)

        with application.test_client() as client:
            response = client.get("/healthz")

        assert response.status_code == 200
        data = response.get_json()
        assert data["status"] == "ok"
        assert "time" in data

    def test_proposed_subscriber_endpoint_is_registered(self) -> None:
        service = MagicMock()
        application = create_application(service)

        with application.test_client() as client:
            response = client.post("/pubsub/proposed", json={}, content_type="application/json")

        # Empty body triggers decode error (400)
        assert response.status_code == 400

    def test_demo_completed_subscriber_endpoint_is_registered(self) -> None:
        service = MagicMock()
        application = create_application(service)

        with application.test_client() as client:
            response = client.post("/pubsub/demo-completed", json={}, content_type="application/json")

        # Empty body triggers decode error (400)
        assert response.status_code == 400

    def test_service_is_stored_in_config(self) -> None:
        service = MagicMock()
        application = create_application(service)

        assert application.config["HYPOTHESIS_WORKFLOW_SERVICE"] is service
