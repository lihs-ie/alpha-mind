"""Tests for CloudEvents envelope decoder."""

from __future__ import annotations

import base64
import json
from datetime import date

import pytest

from signal_generator.presentation.cloud_event_decoder import (
    CloudEventDecodeError,
    CloudEventPayload,
    decode_pubsub_push_message,
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
    """Build a valid CloudEvents JSON envelope."""
    if payload is None:
        payload = {
            "targetDate": "2026-03-05",
            "featureVersion": "v1.0.0",
            "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
        }
    return {
        "identifier": identifier,
        "eventType": event_type,
        "occurredAt": occurred_at,
        "trace": trace,
        "schemaVersion": schema_version,
        "payload": payload,
    }


def _build_pubsub_message(cloud_event: dict[str, object]) -> dict[str, object]:
    """Wrap a CloudEvent in a Pub/Sub push message envelope."""
    encoded = base64.b64encode(json.dumps(cloud_event).encode()).decode()
    return {
        "message": {
            "data": encoded,
            "messageId": "msg-001",
            "publishTime": "2026-03-05T09:00:00Z",
        },
        "subscription": "projects/test/subscriptions/signal-generator-sub",
    }


class TestDecodeValidMessage:
    """Valid Pub/Sub push message decoding."""

    def test_decodes_valid_message(self) -> None:
        cloud_event = _build_cloud_event()
        message = _build_pubsub_message(cloud_event)

        result = decode_pubsub_push_message(message)

        assert isinstance(result, CloudEventPayload)
        assert result.identifier == "01JARQ0000AAAAAAAAAAAAAAAA"
        assert result.event_type == "features.generated"
        assert result.trace == "01JARQ0000BBBBBBBBBBBBBBBB"
        assert result.schema_version == "1.0.0"
        assert result.target_date == date(2026, 3, 5)
        assert result.feature_version == "v1.0.0"
        assert result.storage_path == "gs://features/2026-03-05/v1.0.0.parquet"

    def test_decodes_payload_with_universe_count(self) -> None:
        payload = {
            "targetDate": "2026-03-05",
            "featureVersion": "v1.0.0",
            "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
            "universeCount": 500,
        }
        cloud_event = _build_cloud_event(payload=payload)
        message = _build_pubsub_message(cloud_event)

        result = decode_pubsub_push_message(message)

        assert result.universe_count == 500

    def test_universe_count_defaults_to_none(self) -> None:
        cloud_event = _build_cloud_event()
        message = _build_pubsub_message(cloud_event)

        result = decode_pubsub_push_message(message)

        assert result.universe_count is None

    def test_occurred_at_is_preserved(self) -> None:
        cloud_event = _build_cloud_event(occurred_at="2026-01-15T14:30:00Z")
        message = _build_pubsub_message(cloud_event)

        result = decode_pubsub_push_message(message)

        assert result.occurred_at == "2026-01-15T14:30:00Z"


class TestInvalidPubsubEnvelope:
    """Invalid Pub/Sub envelope structure."""

    def test_missing_message_key(self) -> None:
        with pytest.raises(CloudEventDecodeError, match="message"):
            decode_pubsub_push_message({"subscription": "sub-001"})

    def test_missing_data_key(self) -> None:
        message = {"message": {"messageId": "msg-001"}, "subscription": "sub-001"}
        with pytest.raises(CloudEventDecodeError, match="data"):
            decode_pubsub_push_message(message)

    def test_invalid_base64_data(self) -> None:
        message = {
            "message": {
                "data": "!!!not-valid-base64!!!",
                "messageId": "msg-001",
            },
            "subscription": "sub-001",
        }
        with pytest.raises(CloudEventDecodeError, match="base64"):
            decode_pubsub_push_message(message)

    def test_invalid_json_after_base64_decode(self) -> None:
        encoded = base64.b64encode(b"not json").decode()
        message = {
            "message": {"data": encoded, "messageId": "msg-001"},
            "subscription": "sub-001",
        }
        with pytest.raises(CloudEventDecodeError, match="JSON"):
            decode_pubsub_push_message(message)


class TestInvalidCloudEventEnvelope:
    """Invalid CloudEvents envelope fields."""

    def test_wrong_event_type(self) -> None:
        cloud_event = _build_cloud_event(event_type="data.collected")
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="eventType"):
            decode_pubsub_push_message(message)

    def test_missing_identifier(self) -> None:
        cloud_event = _build_cloud_event()
        del cloud_event["identifier"]
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="identifier"):
            decode_pubsub_push_message(message)

    def test_missing_trace(self) -> None:
        cloud_event = _build_cloud_event()
        del cloud_event["trace"]
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="trace"):
            decode_pubsub_push_message(message)

    def test_missing_payload(self) -> None:
        cloud_event = _build_cloud_event()
        del cloud_event["payload"]
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="payload"):
            decode_pubsub_push_message(message)

    def test_missing_target_date_in_payload(self) -> None:
        payload: dict[str, object] = {
            "featureVersion": "v1.0.0",
            "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
        }
        cloud_event = _build_cloud_event(payload=payload)
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="targetDate"):
            decode_pubsub_push_message(message)

    def test_missing_feature_version_in_payload(self) -> None:
        payload: dict[str, object] = {
            "targetDate": "2026-03-05",
            "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
        }
        cloud_event = _build_cloud_event(payload=payload)
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="featureVersion"):
            decode_pubsub_push_message(message)

    def test_missing_storage_path_in_payload(self) -> None:
        payload: dict[str, object] = {
            "targetDate": "2026-03-05",
            "featureVersion": "v1.0.0",
        }
        cloud_event = _build_cloud_event(payload=payload)
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="storagePath"):
            decode_pubsub_push_message(message)

    def test_invalid_target_date_format(self) -> None:
        payload: dict[str, object] = {
            "targetDate": "not-a-date",
            "featureVersion": "v1.0.0",
            "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
        }
        cloud_event = _build_cloud_event(payload=payload)
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="targetDate"):
            decode_pubsub_push_message(message)

    def test_decoded_json_is_not_object(self) -> None:
        """Base64 + JSON が配列など dict 以外の場合にエラーを送出する。"""
        encoded = base64.b64encode(json.dumps([1, 2, 3]).encode()).decode()
        message: dict[str, object] = {
            "message": {"data": encoded, "messageId": "msg-001"},
            "subscription": "sub-001",
        }
        with pytest.raises(CloudEventDecodeError, match="not an object"):
            decode_pubsub_push_message(message)

    def test_invalid_universe_count_type(self) -> None:
        """universeCount が int でない場合にエラーを送出する。"""
        payload: dict[str, object] = {
            "targetDate": "2026-03-05",
            "featureVersion": "v1.0.0",
            "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
            "universeCount": "not-an-int",
        }
        cloud_event = _build_cloud_event(payload=payload)
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="universeCount"):
            decode_pubsub_push_message(message)
