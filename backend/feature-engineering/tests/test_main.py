"""Tests for feature-engineering main module."""

from __future__ import annotations

import os
from unittest.mock import MagicMock, patch

from main import main


class TestMain:
    """Tests for main() entry point."""

    @patch("main.DependencyContainer")
    @patch("main.create_application")
    def test_main_creates_app_and_runs(
        self,
        mock_create_application: MagicMock,
        mock_dependency_container_class: MagicMock,
    ) -> None:
        mock_container = MagicMock()
        mock_dependency_container_class.return_value = mock_container
        mock_service = MagicMock()
        mock_container.feature_generation_service.return_value = mock_service

        mock_app = MagicMock()
        mock_create_application.return_value = mock_app

        with patch.dict(os.environ, {"PORT": "9090"}, clear=False):
            main()

        mock_dependency_container_class.assert_called_once()
        mock_container.feature_generation_service.assert_called_once()
        mock_create_application.assert_called_once_with(mock_service)
        mock_app.run.assert_called_once_with(host="0.0.0.0", port=9090)

    @patch("main.DependencyContainer")
    @patch("main.create_application")
    def test_main_defaults_to_port_8080(
        self,
        mock_create_application: MagicMock,
        mock_dependency_container_class: MagicMock,
    ) -> None:
        mock_container = MagicMock()
        mock_dependency_container_class.return_value = mock_container
        mock_service = MagicMock()
        mock_container.feature_generation_service.return_value = mock_service

        mock_app = MagicMock()
        mock_create_application.return_value = mock_app

        with patch.dict(os.environ, {}, clear=False):
            # Remove PORT if it exists
            env_copy = dict(os.environ)
            env_copy.pop("PORT", None)
            with patch.dict(os.environ, env_copy, clear=True):
                main()

        mock_app.run.assert_called_once_with(host="0.0.0.0", port=8080)
