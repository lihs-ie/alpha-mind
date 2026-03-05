"""Health check endpoint blueprint."""

from __future__ import annotations

from flask import Blueprint, Response, jsonify

health_blueprint = Blueprint("health", __name__)


@health_blueprint.route("/healthz", methods=["GET"])
def healthz() -> tuple[Response, int]:
    """ヘルスチェックエンドポイント。

    Cloud Run のヘルスチェックプローブが使用する。
    """
    return jsonify({"status": "ok", "service": "signal-generator"}), 200
