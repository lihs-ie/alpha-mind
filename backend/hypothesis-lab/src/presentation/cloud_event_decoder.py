"""CloudEvents decoder for Pub/Sub push messages for hypothesis-lab service.

Decodes Pub/Sub push envelope into EventEnvelope for hypothesis workflow events.
Supports both hypothesis.proposed and hypothesis.demo.completed event types.
"""

from __future__ import annotations

import base64
import datetime
import json
from collections.abc import Mapping

from alpha_mind_backend_common.messaging.cloud_events import (
    CloudEventDecodeError,
    require_mapping_field,
    require_string_field,
    require_ulid_field,
)
from application.hypothesis_workflow_service import EventEnvelope

__all__ = ["CloudEventDecodeError", "decode_pubsub_push_message"]

_EXPECTED_EVENT_TYPES = frozenset({"hypothesis.proposed", "hypothesis.demo.completed"})

_ULID_PATTERN_LENGTH = 26


def decode_pubsub_push_message(body: dict[str, object]) -> EventEnvelope:
    """Decode a Pub/Sub push body into an EventEnvelope.

    Args:
        body: The raw JSON-parsed Pub/Sub push request body.

    Returns:
        Normalized EventEnvelope for use by HypothesisWorkflowService.

    Raises:
        CloudEventDecodeError: If the body cannot be decoded as a valid CloudEvent
            or contains an unexpected event type.
    """
    message = body.get("message")
    if not isinstance(message, dict):
        raise CloudEventDecodeError("Missing or invalid 'message' key in push body")

    data_encoded = message.get("data")
    if not isinstance(data_encoded, str):
        raise CloudEventDecodeError("Missing or invalid 'data' key in message")

    try:
        data_bytes = base64.b64decode(data_encoded, validate=True)
    except Exception as error:
        raise CloudEventDecodeError(f"Failed to decode base64 data: {error}") from error

    try:
        decoded_object = json.loads(data_bytes)
    except json.JSONDecodeError as error:
        raise CloudEventDecodeError(f"Failed to parse JSON from decoded data: {error}") from error

    if not isinstance(decoded_object, dict):
        raise CloudEventDecodeError("Decoded JSON is not an object")

    cloud_event: Mapping[str, object] = decoded_object

    identifier = require_ulid_field(cloud_event, "identifier")
    trace = require_ulid_field(cloud_event, "trace")
    event_type = require_string_field(cloud_event, "eventType")
    occurred_at_raw = require_string_field(cloud_event, "occurredAt")
    payload = require_mapping_field(cloud_event, "payload")

    if event_type not in _EXPECTED_EVENT_TYPES:
        raise CloudEventDecodeError(
            f"Unexpected eventType: got '{event_type}', expected one of {sorted(_EXPECTED_EVENT_TYPES)}"
        )

    occurred_at = _parse_occurred_at(occurred_at_raw)

    return EventEnvelope(
        identifier=identifier,
        event_type=event_type,
        occurred_at=occurred_at,
        trace=trace,
        payload=payload,
    )


def _parse_occurred_at(value: str) -> datetime.datetime:
    """Parse an ISO8601 UTC datetime string into a datetime object."""
    normalized = value.replace("Z", "+00:00")
    try:
        occurred_at = datetime.datetime.fromisoformat(normalized)
    except ValueError as error:
        raise CloudEventDecodeError(f"occurredAt must be an ISO 8601 timestamp: '{value}'") from error
    if occurred_at.tzinfo is None:
        raise CloudEventDecodeError(f"occurredAt must be timezone-aware: '{value}'")
    return occurred_at.astimezone(datetime.UTC)
