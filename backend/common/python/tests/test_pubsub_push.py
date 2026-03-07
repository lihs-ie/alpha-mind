"""Tests for shared Pub/Sub push CloudEvents decoding."""

from __future__ import annotations

import base64
import json

import pytest

from alpha_mind_backend_common.messaging.cloud_events import CloudEventDecodeError
from alpha_mind_backend_common.messaging.pubsub_push import (
    decode_pubsub_push_envelope,
    extract_pubsub_push_identifiers,
)


def _build_cloud_event(
    *,
    identifier: str = "01JARQ0000AAAAAAAAAAAAAAAA",
    event_type: str = "features.generated",
    occurred_at: str = "2026-03-05T09:00:00Z",
    trace: str = "01JARQ0000BBBBBBBBBBBBBBBB",
    schema_version: str = "1.0.0",
    payload: dict[str, object] | None = None,
) -> dict[str, object]:
    """Builds a CloudEvents envelope."""
    return {
        "identifier": identifier,
        "eventType": event_type,
        "occurredAt": occurred_at,
        "trace": trace,
        "schemaVersion": schema_version,
        "payload": payload or {"value": "ok"},
    }


def _build_pubsub_message(cloud_event: dict[str, object]) -> dict[str, object]:
    """Wraps a CloudEvents envelope in a Pub/Sub push body."""
    encoded = base64.b64encode(json.dumps(cloud_event).encode("utf-8")).decode("utf-8")
    return {
        "message": {
            "data": encoded,
            "messageId": "msg-001",
        },
        "subscription": "projects/test/subscriptions/test-sub",
    }


def test_decode_pubsub_push_envelope_returns_envelope() -> None:
    """Decodes a valid Pub/Sub push message into a normalized envelope."""
    message = _build_pubsub_message(_build_cloud_event())

    envelope = decode_pubsub_push_envelope(message, expected_event_type="features.generated")

    assert envelope.identifier == "01JARQ0000AAAAAAAAAAAAAAAA"
    assert envelope.event_type == "features.generated"
    assert envelope.trace == "01JARQ0000BBBBBBBBBBBBBBBB"
    assert envelope.schema_version == "1.0.0"
    assert envelope.payload == {"value": "ok"}


def test_decode_pubsub_push_envelope_rejects_wrong_event_type() -> None:
    """Rejects envelopes with an unexpected event type."""
    message = _build_pubsub_message(_build_cloud_event(event_type="market.collected"))

    with pytest.raises(CloudEventDecodeError, match="eventType"):
        decode_pubsub_push_envelope(message, expected_event_type="features.generated")


def test_decode_pubsub_push_envelope_rejects_invalid_base64() -> None:
    """Rejects invalid base64 data."""
    message: dict[str, object] = {
        "message": {"data": "!!!invalid!!!"},
    }

    with pytest.raises(CloudEventDecodeError, match="base64"):
        decode_pubsub_push_envelope(message, expected_event_type="features.generated")


def test_decode_pubsub_push_envelope_rejects_missing_payload() -> None:
    """Rejects envelopes without payload."""
    cloud_event = _build_cloud_event()
    del cloud_event["payload"]
    message = _build_pubsub_message(cloud_event)

    with pytest.raises(CloudEventDecodeError, match="payload"):
        decode_pubsub_push_envelope(message, expected_event_type="features.generated")


def test_extract_pubsub_push_identifiers_returns_values_when_present() -> None:
    """Extracts identifier and trace when both are valid ULIDs."""
    message = _build_pubsub_message(_build_cloud_event())

    assert extract_pubsub_push_identifiers(message) == (
        "01JARQ0000AAAAAAAAAAAAAAAA",
        "01JARQ0000BBBBBBBBBBBBBBBB",
    )


def test_extract_pubsub_push_identifiers_returns_none_for_invalid_envelope() -> None:
    """Returns None when identifier or trace cannot be extracted safely."""
    message = _build_pubsub_message(_build_cloud_event(identifier="invalid"))

    assert extract_pubsub_push_identifiers(message) is None
