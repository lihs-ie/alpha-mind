"""Tests for CloudEvents decoder for hypothesis-lab service."""

from __future__ import annotations

import base64
import datetime
import json
from typing import Any

import pytest

from alpha_mind_backend_common.messaging.cloud_events import CloudEventDecodeError
from application.hypothesis_workflow_service import EventEnvelope
from presentation.cloud_event_decoder import decode_pubsub_push_message


def _make_pubsub_body(
    identifier: str = "01JQXK5V6R3YBNM7GTWP0HS4EA",
    event_type: str = "hypothesis.proposed",
    occurred_at: str = "2026-03-05T09:00:00Z",
    trace: str = "01JQXK5V6R3YBNM7GTWP0HS4EB",
    schema_version: str = "1.0",
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if payload is None:
        payload = {"title": "Test hypothesis", "symbol": "1234"}
    cloud_event: dict[str, Any] = {
        "identifier": identifier,
        "eventType": event_type,
        "occurredAt": occurred_at,
        "trace": trace,
        "schemaVersion": schema_version,
        "payload": payload,
    }
    encoded = base64.b64encode(json.dumps(cloud_event).encode("utf-8")).decode("utf-8")
    return {
        "message": {
            "data": encoded,
            "messageId": "msg-123",
            "publishTime": "2026-03-05T09:00:00Z",
        },
        "subscription": "projects/test/subscriptions/test-sub",
    }


class TestDecodePubsubPushMessage:
    """Tests for decode_pubsub_push_message."""

    def test_decodes_hypothesis_proposed_event(self) -> None:
        body = _make_pubsub_body(event_type="hypothesis.proposed")
        envelope = decode_pubsub_push_message(body)

        assert isinstance(envelope, EventEnvelope)
        assert envelope.identifier == "01JQXK5V6R3YBNM7GTWP0HS4EA"
        assert envelope.event_type == "hypothesis.proposed"
        assert envelope.trace == "01JQXK5V6R3YBNM7GTWP0HS4EB"

    def test_decodes_hypothesis_demo_completed_event(self) -> None:
        body = _make_pubsub_body(event_type="hypothesis.demo.completed")
        envelope = decode_pubsub_push_message(body)

        assert isinstance(envelope, EventEnvelope)
        assert envelope.event_type == "hypothesis.demo.completed"

    def test_occurred_at_is_parsed_as_utc_datetime(self) -> None:
        body = _make_pubsub_body(occurred_at="2026-03-05T09:00:00Z")
        envelope = decode_pubsub_push_message(body)

        assert isinstance(envelope.occurred_at, datetime.datetime)
        assert envelope.occurred_at.tzinfo is not None
        assert envelope.occurred_at.year == 2026
        assert envelope.occurred_at.month == 3
        assert envelope.occurred_at.day == 5

    def test_payload_is_preserved(self) -> None:
        payload = {"title": "Test", "symbol": "7203"}
        body = _make_pubsub_body(payload=payload)
        envelope = decode_pubsub_push_message(body)

        assert envelope.payload["title"] == "Test"
        assert envelope.payload["symbol"] == "7203"

    def test_missing_message_raises_decode_error(self) -> None:
        with pytest.raises(CloudEventDecodeError, match="message"):
            decode_pubsub_push_message({})

    def test_missing_data_raises_decode_error(self) -> None:
        with pytest.raises(CloudEventDecodeError, match="data"):
            decode_pubsub_push_message({"message": {}})

    def test_invalid_base64_raises_decode_error(self) -> None:
        with pytest.raises(CloudEventDecodeError, match="base64"):
            decode_pubsub_push_message({"message": {"data": "not!!valid!!base64!!"}})

    def test_invalid_json_raises_decode_error(self) -> None:
        invalid_json = base64.b64encode(b"not json").decode()
        with pytest.raises(CloudEventDecodeError, match="JSON"):
            decode_pubsub_push_message({"message": {"data": invalid_json}})

    def test_unexpected_event_type_raises_decode_error(self) -> None:
        body = _make_pubsub_body(event_type="market.collected")
        with pytest.raises(CloudEventDecodeError, match="eventType"):
            decode_pubsub_push_message(body)

    def test_invalid_occurred_at_raises_decode_error(self) -> None:
        body = _make_pubsub_body(occurred_at="not-a-date")
        with pytest.raises(CloudEventDecodeError, match="ISO 8601"):
            decode_pubsub_push_message(body)

    def test_invalid_identifier_ulid_raises_decode_error(self) -> None:
        body = _make_pubsub_body(identifier="not-a-ulid")
        with pytest.raises(CloudEventDecodeError, match="identifier"):
            decode_pubsub_push_message(body)

    def test_missing_payload_raises_decode_error(self) -> None:
        cloud_event: dict[str, Any] = {
            "identifier": "01JQXK5V6R3YBNM7GTWP0HS4EA",
            "eventType": "hypothesis.proposed",
            "occurredAt": "2026-03-05T09:00:00Z",
            "trace": "01JQXK5V6R3YBNM7GTWP0HS4EB",
            "schemaVersion": "1.0",
        }
        encoded = base64.b64encode(json.dumps(cloud_event).encode()).decode()
        body = {"message": {"data": encoded}}
        with pytest.raises(CloudEventDecodeError, match="payload"):
            decode_pubsub_push_message(body)
