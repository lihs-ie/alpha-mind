"""Tests for signal-generator main module."""

from __future__ import annotations

import os
from unittest.mock import MagicMock, patch

import flask


class TestMainModule:
    """main.py module tests."""

    def test_create_app_returns_flask_application(self) -> None:
        """create_app() はFlask アプリケーションを返す。"""
        with patch(
            "signal_generator.presentation.dependency_container._build_signal_generation_service"
        ) as mock_build:
            mock_build.return_value = MagicMock()
            from main import create_app

            application = create_app()
            assert isinstance(application, flask.Flask)

    def test_healthz_accessible_via_app(self) -> None:
        """create_app() で作成したアプリの /healthz が応答する。"""
        with patch(
            "signal_generator.presentation.dependency_container._build_signal_generation_service"
        ) as mock_build:
            mock_build.return_value = MagicMock()
            from main import create_app

            application = create_app()
            client = application.test_client()
            response = client.get("/healthz")
            assert response.status_code == 200


class TestMainFunction:
    """main() function tests."""

    def test_main_starts_flask_app_on_default_port(self) -> None:
        """main() は Flask アプリの run を呼び出す。"""
        with (
            patch(
                "signal_generator.presentation.dependency_container._build_signal_generation_service"
            ) as mock_build,
            patch.dict(os.environ, {}, clear=False),
        ):
            mock_build.return_value = MagicMock()
            os.environ.pop("PORT", None)
            from main import main

            with patch("main.create_app") as mock_create_app:
                mock_app = MagicMock()
                mock_create_app.return_value = mock_app
                main()
                mock_app.run.assert_called_once_with(host="0.0.0.0", port=8080)

    def test_main_uses_port_from_environment(self) -> None:
        """main() は PORT 環境変数を使用する。"""
        with (
            patch(
                "signal_generator.presentation.dependency_container._build_signal_generation_service"
            ) as mock_build,
            patch.dict(os.environ, {"PORT": "9090"}),
        ):
            mock_build.return_value = MagicMock()
            from main import main

            with patch("main.create_app") as mock_create_app:
                mock_app = MagicMock()
                mock_create_app.return_value = mock_app
                main()
                mock_app.run.assert_called_once_with(host="0.0.0.0", port=9090)


