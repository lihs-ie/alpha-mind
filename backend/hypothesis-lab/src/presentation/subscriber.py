"""Pub/Sub push subscriber Blueprint for hypothesis-lab service.

Receives hypothesis.proposed and hypothesis.demo.completed events via Pub/Sub
push delivery, decodes the CloudEvents envelope, and invokes the
HypothesisWorkflowService use case.
"""

from __future__ import annotations

import logging
from typing import Any

import flask

from application.hypothesis_workflow_service import HypothesisProcessingError
from presentation.cloud_event_decoder import CloudEventDecodeError, decode_pubsub_push_message

logger = logging.getLogger(__name__)

SERVICE_NAME = "hypothesis-lab"

subscriber_blueprint = flask.Blueprint("subscriber", __name__)


@subscriber_blueprint.route("/pubsub/proposed", methods=["POST"])
def handle_hypothesis_proposed() -> flask.Response:
    """Handle hypothesis.proposed Pub/Sub push messages.

    Returns:
        204: Message processed successfully (ack).
        400: Decode error or invalid message (ack, no retry).
        500: Transient error (nack, Pub/Sub will retry).
    """
    request_json: dict[str, Any] | None = flask.request.get_json(silent=True)
    if request_json is None:
        logger.warning(
            "Received non-JSON request body",
            extra={
                "service": SERVICE_NAME,
                "identifier": "unknown",
                "trace": "unknown",
                "eventType": "hypothesis.proposed",
                "reasonCode": "REQUEST_VALIDATION_FAILED",
            },
        )
        return flask.Response("Invalid request: expected JSON body", status=400)

    try:
        envelope = decode_pubsub_push_message(request_json)
    except CloudEventDecodeError as error:
        logger.warning(
            "CloudEvent decode error: %s",
            error,
            extra={
                "service": SERVICE_NAME,
                "identifier": "unknown",
                "trace": "unknown",
                "eventType": "hypothesis.proposed",
                "reasonCode": "REQUEST_VALIDATION_FAILED",
            },
        )
        return flask.Response(f"Decode error: {error}", status=400)

    hypothesis_workflow_service = flask.current_app.config["HYPOTHESIS_WORKFLOW_SERVICE"]

    try:
        hypothesis_workflow_service.process_proposed(envelope)
    except HypothesisProcessingError as error:
        if error.retryable:
            logger.exception(
                "Retryable error processing hypothesis.proposed event: %s",
                error,
                extra={
                    "service": SERVICE_NAME,
                    "identifier": envelope.identifier,
                    "trace": envelope.trace,
                    "eventType": "hypothesis.proposed",
                },
            )
            return flask.Response("Retryable error", status=500)
        logger.warning(
            "Non-retryable error processing hypothesis.proposed event: %s",
            error,
            extra={
                "service": SERVICE_NAME,
                "identifier": envelope.identifier,
                "trace": envelope.trace,
                "eventType": "hypothesis.proposed",
                "reasonCode": error.reason_code.value,
            },
        )
        return flask.Response(f"Processing error: {error}", status=400)
    except Exception as error:
        logger.exception(
            "Unexpected error processing hypothesis.proposed event: %s",
            error,
            extra={
                "service": SERVICE_NAME,
                "identifier": envelope.identifier,
                "trace": envelope.trace,
                "eventType": "hypothesis.proposed",
            },
        )
        return flask.Response("Internal server error", status=500)

    logger.info(
        "Successfully processed hypothesis.proposed event",
        extra={
            "service": SERVICE_NAME,
            "identifier": envelope.identifier,
            "trace": envelope.trace,
            "eventType": "hypothesis.proposed",
        },
    )
    return flask.Response(status=204)


@subscriber_blueprint.route("/pubsub/demo-completed", methods=["POST"])
def handle_hypothesis_demo_completed() -> flask.Response:
    """Handle hypothesis.demo.completed Pub/Sub push messages.

    Returns:
        204: Message processed successfully (ack).
        400: Decode error or invalid message (ack, no retry).
        500: Transient error (nack, Pub/Sub will retry).
    """
    request_json: dict[str, Any] | None = flask.request.get_json(silent=True)
    if request_json is None:
        logger.warning(
            "Received non-JSON request body",
            extra={
                "service": SERVICE_NAME,
                "identifier": "unknown",
                "trace": "unknown",
                "eventType": "hypothesis.demo.completed",
                "reasonCode": "REQUEST_VALIDATION_FAILED",
            },
        )
        return flask.Response("Invalid request: expected JSON body", status=400)

    try:
        envelope = decode_pubsub_push_message(request_json)
    except CloudEventDecodeError as error:
        logger.warning(
            "CloudEvent decode error: %s",
            error,
            extra={
                "service": SERVICE_NAME,
                "identifier": "unknown",
                "trace": "unknown",
                "eventType": "hypothesis.demo.completed",
                "reasonCode": "REQUEST_VALIDATION_FAILED",
            },
        )
        return flask.Response(f"Decode error: {error}", status=400)

    hypothesis_workflow_service = flask.current_app.config["HYPOTHESIS_WORKFLOW_SERVICE"]

    try:
        hypothesis_workflow_service.process_demo_completed(envelope)
    except HypothesisProcessingError as error:
        if error.retryable:
            logger.exception(
                "Retryable error processing hypothesis.demo.completed event: %s",
                error,
                extra={
                    "service": SERVICE_NAME,
                    "identifier": envelope.identifier,
                    "trace": envelope.trace,
                    "eventType": "hypothesis.demo.completed",
                },
            )
            return flask.Response("Retryable error", status=500)
        logger.warning(
            "Non-retryable error processing hypothesis.demo.completed event: %s",
            error,
            extra={
                "service": SERVICE_NAME,
                "identifier": envelope.identifier,
                "trace": envelope.trace,
                "eventType": "hypothesis.demo.completed",
                "reasonCode": error.reason_code.value,
            },
        )
        return flask.Response(f"Processing error: {error}", status=400)
    except Exception as error:
        logger.exception(
            "Unexpected error processing hypothesis.demo.completed event: %s",
            error,
            extra={
                "service": SERVICE_NAME,
                "identifier": envelope.identifier,
                "trace": envelope.trace,
                "eventType": "hypothesis.demo.completed",
            },
        )
        return flask.Response("Internal server error", status=500)

    logger.info(
        "Successfully processed hypothesis.demo.completed event",
        extra={
            "service": SERVICE_NAME,
            "identifier": envelope.identifier,
            "trace": envelope.trace,
            "eventType": "hypothesis.demo.completed",
        },
    )
    return flask.Response(status=204)
