"""Health check Blueprint for feature-engineering service."""

from __future__ import annotations

import flask

health_blueprint = flask.Blueprint("health", __name__)


@health_blueprint.route("/healthz", methods=["GET"])
def healthz() -> flask.Response:
    """Return 200 OK to indicate the service is healthy."""
    return flask.Response("ok", status=200, content_type="text/plain")
