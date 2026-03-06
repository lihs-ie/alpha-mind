"""Tests for CloudEvents decoder."""

from __future__ import annotations

import base64
import datetime
import json

import pytest

from domain.value_object.enums import SourceStatusValue
from presentation.cloud_event_decoder import CloudEventDecodeError, decode_pubsub_push_message


class TestDecodePubsubPushMessage:
    """Tests for decode_pubsub_push_message function."""

    @staticmethod
    def _make_valid_payload() -> dict[str, object]:
        return {
            "identifier": "01JQXK5V6R3YBNM7GTWP0HS4EA",
            "eventType": "market.collected",
            "occurredAt": "2026-03-05T09:00:00Z",
            "trace": "01JQXK5V6R3YBNM7GTWP0HS4EB",
            "schemaVersion": "1.0",
            "payload": {
                "targetDate": "2026-03-05",
                "storagePath": "gs://bucket/path/to/data",
                "sourceStatus": {
                    "jp": "ok",
                    "us": "ok",
                },
            },
        }

    @staticmethod
    def _wrap_in_pubsub_message(payload: dict[str, object]) -> dict[str, object]:
        encoded = base64.b64encode(json.dumps(payload).encode("utf-8")).decode("utf-8")
        return {
            "message": {
                "data": encoded,
                "messageId": "msg-123",
                "publishTime": "2026-03-05T09:00:00Z",
            },
            "subscription": "projects/test/subscriptions/test-sub",
        }

    def test_decode_valid_message_returns_tuple(self) -> None:
        payload = self._make_valid_payload()
        pubsub_message = self._wrap_in_pubsub_message(payload)

        identifier, market, trace = decode_pubsub_push_message(pubsub_message)

        assert identifier == "01JQXK5V6R3YBNM7GTWP0HS4EA"
        assert trace == "01JQXK5V6R3YBNM7GTWP0HS4EB"
        assert market.target_date == datetime.date(2026, 3, 5)
        assert market.storage_path == "gs://bucket/path/to/data"
        assert market.source_status.jp == SourceStatusValue.OK
        assert market.source_status.us == SourceStatusValue.OK

    def test_decode_missing_message_key_raises_error(self) -> None:
        with pytest.raises(CloudEventDecodeError, match="message"):
            decode_pubsub_push_message({})

    def test_decode_missing_data_key_raises_error(self) -> None:
        with pytest.raises(CloudEventDecodeError, match="data"):
            decode_pubsub_push_message({"message": {}})

    def test_decode_invalid_base64_raises_error(self) -> None:
        with pytest.raises(CloudEventDecodeError, match="base64"):
            decode_pubsub_push_message({"message": {"data": "!!!invalid!!!"}})

    def test_decode_invalid_json_raises_error(self) -> None:
        encoded = base64.b64encode(b"not json").decode("utf-8")
        with pytest.raises(CloudEventDecodeError, match="JSON"):
            decode_pubsub_push_message({"message": {"data": encoded}})

    def test_decode_missing_identifier_raises_error(self) -> None:
        payload = self._make_valid_payload()
        del payload["identifier"]  # type: ignore[arg-type]
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match="identifier"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_invalid_identifier_format_raises_error(self) -> None:
        payload = self._make_valid_payload()
        payload["identifier"] = "not-a-ulid"
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match=r"identifier.*ULID"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_wrong_event_type_raises_error(self) -> None:
        payload = self._make_valid_payload()
        payload["eventType"] = "signal.generated"
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match="eventType"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_missing_trace_raises_error(self) -> None:
        payload = self._make_valid_payload()
        del payload["trace"]  # type: ignore[arg-type]
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match="trace"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_invalid_trace_format_raises_error(self) -> None:
        payload = self._make_valid_payload()
        payload["trace"] = "bad-trace"
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match=r"trace.*ULID"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_invalid_occurred_at_format_raises_error(self) -> None:
        payload = self._make_valid_payload()
        payload["occurredAt"] = "not-a-datetime"
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match="occurredAt"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_occurred_at_without_timezone_raises_error(self) -> None:
        payload = self._make_valid_payload()
        payload["occurredAt"] = "2026-03-05T09:00:00"
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match="occurredAt"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_missing_occurred_at_raises_error(self) -> None:
        payload = self._make_valid_payload()
        del payload["occurredAt"]  # type: ignore[arg-type]
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match="occurredAt"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_missing_schema_version_raises_error(self) -> None:
        payload = self._make_valid_payload()
        del payload["schemaVersion"]  # type: ignore[arg-type]
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match="schemaVersion"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_missing_payload_raises_error(self) -> None:
        payload = self._make_valid_payload()
        del payload["payload"]  # type: ignore[arg-type]
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match="payload"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_missing_target_date_raises_error(self) -> None:
        payload = self._make_valid_payload()
        inner = dict(payload["payload"])  # type: ignore[arg-type]
        del inner["targetDate"]
        payload["payload"] = inner
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match="targetDate"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_missing_storage_path_raises_error(self) -> None:
        payload = self._make_valid_payload()
        inner = dict(payload["payload"])  # type: ignore[arg-type]
        del inner["storagePath"]
        payload["payload"] = inner
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match="storagePath"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_missing_source_status_raises_error(self) -> None:
        payload = self._make_valid_payload()
        inner = dict(payload["payload"])  # type: ignore[arg-type]
        del inner["sourceStatus"]
        payload["payload"] = inner
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match="sourceStatus"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_invalid_source_status_value_raises_error(self) -> None:
        payload = self._make_valid_payload()
        inner = dict(payload["payload"])  # type: ignore[arg-type]
        inner["sourceStatus"] = {"jp": "invalid", "us": "ok"}
        payload["payload"] = inner
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match="sourceStatus"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_invalid_target_date_format_raises_error(self) -> None:
        payload = self._make_valid_payload()
        inner = dict(payload["payload"])  # type: ignore[arg-type]
        inner["targetDate"] = "not-a-date"
        payload["payload"] = inner
        pubsub_message = self._wrap_in_pubsub_message(payload)

        with pytest.raises(CloudEventDecodeError, match="targetDate"):
            decode_pubsub_push_message(pubsub_message)

    def test_decode_us_failed_source_status(self) -> None:
        payload = self._make_valid_payload()
        inner = dict(payload["payload"])  # type: ignore[arg-type]
        inner["sourceStatus"] = {"jp": "ok", "us": "failed"}
        payload["payload"] = inner
        pubsub_message = self._wrap_in_pubsub_message(payload)

        _identifier, market, _trace = decode_pubsub_push_message(pubsub_message)

        assert market.source_status.us == SourceStatusValue.FAILED
        assert market.source_status.jp == SourceStatusValue.OK
