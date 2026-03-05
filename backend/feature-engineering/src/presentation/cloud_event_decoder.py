"""CloudEvents decoder for Pub/Sub push messages.

Decodes and validates incoming Pub/Sub push messages containing CloudEvents
envelopes for market.collected events.
"""

from __future__ import annotations

import base64
import datetime
import json
import re
from typing import Any

from domain.value_object.enums import SourceStatusValue
from domain.value_object.market_snapshot import MarketSnapshot
from domain.value_object.source_status import SourceStatus

_ULID_PATTERN = re.compile(r"^[0-9A-HJKMNP-TV-Z]{26}$")
_EXPECTED_EVENT_TYPE = "market.collected"


class CloudEventDecodeError(Exception):
    """Raised when a Pub/Sub push message cannot be decoded as a valid CloudEvent."""


def decode_pubsub_push_message(
    body: dict[str, Any],
) -> tuple[str, MarketSnapshot, str]:
    """Decode a Pub/Sub push message into (identifier, MarketSnapshot, trace).

    Args:
        body: The raw JSON body from the Pub/Sub push endpoint.

    Returns:
        A tuple of (identifier, MarketSnapshot, trace).

    Raises:
        CloudEventDecodeError: If the message is malformed or fails validation.
    """
    # Extract message.data (base64-encoded)
    message = body.get("message")
    if not isinstance(message, dict):
        raise CloudEventDecodeError("Missing or invalid 'message' key in push body")

    raw_data = message.get("data")
    if not isinstance(raw_data, str):
        raise CloudEventDecodeError("Missing or invalid 'data' key in message")

    # Base64 decode
    try:
        decoded_bytes = base64.b64decode(raw_data, validate=True)
    except Exception as error:
        raise CloudEventDecodeError(f"Failed to base64-decode message data: {error}") from error

    # JSON parse
    try:
        envelope: dict[str, Any] = json.loads(decoded_bytes)
    except json.JSONDecodeError as error:
        raise CloudEventDecodeError(f"Failed to parse JSON from decoded data: {error}") from error

    # Validate required CloudEvents attributes
    identifier = _require_string(envelope, "identifier")
    _validate_ulid(identifier, "identifier")

    event_type = _require_string(envelope, "eventType")
    if event_type != _EXPECTED_EVENT_TYPE:
        raise CloudEventDecodeError(
            f"Invalid eventType: expected '{_EXPECTED_EVENT_TYPE}', got '{event_type}'"
        )

    _require_string(envelope, "occurredAt")
    trace = _require_string(envelope, "trace")
    _validate_ulid(trace, "trace")
    _require_string(envelope, "schemaVersion")

    # Extract and validate payload
    payload = envelope.get("payload")
    if not isinstance(payload, dict):
        raise CloudEventDecodeError("Missing or invalid 'payload' in CloudEvents envelope")

    market = _decode_market_snapshot(payload)

    return identifier, market, trace


def _require_string(data: dict[str, Any], key: str) -> str:
    """Extract a required string field from a dictionary."""
    value = data.get(key)
    if not isinstance(value, str) or not value:
        raise CloudEventDecodeError(f"Missing or invalid required field '{key}'")
    return value


def _validate_ulid(value: str, field_name: str) -> None:
    """Validate that a string matches the ULID format."""
    if not _ULID_PATTERN.match(value):
        raise CloudEventDecodeError(
            f"Field '{field_name}' must be a valid ULID (26-character Crockford Base32), got '{value}'"
        )


def _decode_market_snapshot(payload: dict[str, Any]) -> MarketSnapshot:
    """Decode the payload section into a MarketSnapshot value object."""
    target_date_string = _require_string(payload, "targetDate")
    try:
        target_date = datetime.date.fromisoformat(target_date_string)
    except ValueError as error:
        raise CloudEventDecodeError(
            f"Invalid 'targetDate' format: {target_date_string}"
        ) from error

    storage_path = _require_string(payload, "storagePath")

    source_status_data = payload.get("sourceStatus")
    if not isinstance(source_status_data, dict):
        raise CloudEventDecodeError("Missing or invalid 'sourceStatus' in payload")

    try:
        source_status = SourceStatus(
            jp=SourceStatusValue(source_status_data.get("jp", "")),
            us=SourceStatusValue(source_status_data.get("us", "")),
        )
    except ValueError as error:
        raise CloudEventDecodeError(
            f"Invalid 'sourceStatus' value: {error}"
        ) from error

    return MarketSnapshot(
        target_date=target_date,
        storage_path=storage_path,
        source_status=source_status,
    )
