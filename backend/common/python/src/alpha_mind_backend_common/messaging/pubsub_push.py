"""Shared Pub/Sub push decoding helpers."""

from __future__ import annotations

import base64
import json
from collections.abc import Mapping
from typing import cast

from alpha_mind_backend_common.messaging.cloud_events import (
    CloudEventDecodeError,
    CloudEventEnvelope,
    require_datetime_field,
    require_mapping_field,
    require_string_field,
    require_ulid_field,
)


def decode_pubsub_push_envelope(
    push_message: Mapping[str, object],
    *,
    expected_event_type: str,
) -> CloudEventEnvelope:
    """Decode a Pub/Sub push message into a normalized CloudEvents envelope."""
    message = _require_mapping(push_message.get("message"), "message")
    data_encoded = message.get("data")
    if not isinstance(data_encoded, str):
        raise CloudEventDecodeError("Missing or invalid 'data' key in message")

    try:
        data_bytes = base64.b64decode(data_encoded, validate=True)
    except Exception as error:
        raise CloudEventDecodeError(f"Failed to decode base64 data: {error}") from error

    try:
        decoded_object = cast(object, json.loads(data_bytes))
    except json.JSONDecodeError as error:
        raise CloudEventDecodeError(f"Failed to parse JSON from decoded data: {error}") from error

    cloud_event = _require_mapping(decoded_object, "decoded JSON")

    identifier = require_ulid_field(cloud_event, "identifier")
    trace = require_ulid_field(cloud_event, "trace")
    event_type = require_string_field(cloud_event, "eventType")
    occurred_at = require_datetime_field(cloud_event, "occurredAt")
    schema_version = require_string_field(cloud_event, "schemaVersion")
    payload = require_mapping_field(cloud_event, "payload")

    if event_type != expected_event_type:
        raise CloudEventDecodeError(f"Unexpected eventType: expected '{expected_event_type}', got '{event_type}'")

    return CloudEventEnvelope(
        identifier=identifier,
        event_type=event_type,
        occurred_at=occurred_at,
        trace=trace,
        schema_version=schema_version,
        payload=payload,
    )


def extract_pubsub_push_identifiers(push_message: Mapping[str, object]) -> tuple[str, str] | None:
    """Best-effort extraction of identifier and trace from a Pub/Sub push body."""
    try:
        message = push_message.get("message")
        if not isinstance(message, dict):
            return None
        data_encoded = message.get("data")
        if not isinstance(data_encoded, str):
            return None
        data_bytes = base64.b64decode(data_encoded, validate=True)
        decoded_object = cast(object, json.loads(data_bytes))
        cloud_event = _require_mapping(decoded_object, "decoded JSON")
        return (
            require_ulid_field(cloud_event, "identifier"),
            require_ulid_field(cloud_event, "trace"),
        )
    except Exception:
        return None


def _require_mapping(value: object, field_name: str) -> Mapping[str, object]:
    """Return a mapping value or raise a decode error."""
    if not isinstance(value, dict):
        if field_name == "decoded JSON":
            raise CloudEventDecodeError("Decoded JSON is not an object")
        raise CloudEventDecodeError(f"Missing or invalid '{field_name}' key in push body")
    return value
