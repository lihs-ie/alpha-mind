"""Health check Blueprint for feature-engineering service."""

from __future__ import annotations

import datetime

import flask

health_blueprint = flask.Blueprint("health", __name__)


@health_blueprint.route("/healthz", methods=["GET"])
def healthz() -> tuple[flask.Response, int]:
    """Return 200 OK with JSON body to indicate the service is healthy."""
    now = datetime.datetime.now(tz=datetime.UTC).isoformat().replace("+00:00", "Z")
    return flask.jsonify({"status": "ok", "time": now}), 200
