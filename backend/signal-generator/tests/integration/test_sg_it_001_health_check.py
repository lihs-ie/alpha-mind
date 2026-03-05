"""SG-IT-001: ヘルスチェック統合テスト。

観点: /healthz エンドポイントが 200 を返すこと。
優先度: P1
"""

from __future__ import annotations

import json

import flask.testing


class TestHealthCheckIntegration:
    """SG-IT-001: ヘルスチェックエンドポイントの統合テスト。"""

    def test_healthz_returns_200(self, client: flask.testing.FlaskClient) -> None:
        """/healthz が HTTP 200 を返す。"""
        response = client.get("/healthz")

        assert response.status_code == 200

    def test_healthz_returns_json_with_status_ok(self, client: flask.testing.FlaskClient) -> None:
        """/healthz のレスポンスボディに status=ok が含まれる。"""
        response = client.get("/healthz")
        data = json.loads(response.data)

        assert data["status"] == "ok"

    def test_healthz_returns_service_name(self, client: flask.testing.FlaskClient) -> None:
        """/healthz のレスポンスボディに service=signal-generator が含まれる。"""
        response = client.get("/healthz")
        data = json.loads(response.data)

        assert data["service"] == "signal-generator"

    def test_healthz_returns_json_content_type(self, client: flask.testing.FlaskClient) -> None:
        """/healthz のレスポンスが application/json を返す。"""
        response = client.get("/healthz")

        assert response.content_type == "application/json"
