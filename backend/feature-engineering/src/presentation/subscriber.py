"""Pub/Sub push subscriber Blueprint for feature-engineering service.

Receives market.collected events via Pub/Sub push delivery,
decodes the CloudEvents envelope, and invokes the feature generation usecase.
"""

from __future__ import annotations

import logging
from typing import Any

import flask

from presentation.cloud_event_decoder import CloudEventDecodeError, decode_pubsub_push_message

logger = logging.getLogger(__name__)

subscriber_blueprint = flask.Blueprint("subscriber", __name__)


@subscriber_blueprint.route("/", methods=["POST"])
def handle_pubsub_push() -> flask.Response:
    """Handle incoming Pub/Sub push messages.

    Returns:
        204: Message processed successfully (ack).
        400: Decode error or invalid message (ack, no retry).
        500: Transient error (nack, Pub/Sub will retry).
    """
    request_json: dict[str, Any] | None = flask.request.get_json(silent=True)
    if request_json is None:
        logger.warning("Received non-JSON request body")
        return flask.Response("Invalid request: expected JSON body", status=400)

    try:
        identifier, market, trace = decode_pubsub_push_message(request_json)
    except CloudEventDecodeError as error:
        logger.warning(
            "CloudEvent decode error: %s",
            error,
            extra={"service": "feature-engineering"},
        )
        return flask.Response(f"Decode error: {error}", status=400)

    feature_generation_service = flask.current_app.config["FEATURE_GENERATION_SERVICE"]

    try:
        feature_generation_service.execute(
            identifier=identifier,
            market=market,
            trace=trace,
        )
    except Exception as error:
        logger.exception(
            "Error processing event identifier=%s trace=%s: %s",
            identifier,
            trace,
            error,
            extra={
                "service": "feature-engineering",
                "identifier": identifier,
                "trace": trace,
            },
        )
        return flask.Response("Internal server error", status=500)

    return flask.Response(status=204)
