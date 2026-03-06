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
            "universeCount": 100,
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
        assert result.universe_count == 100

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

    def test_missing_universe_count_raises_error(self) -> None:
        """universeCount が欠損した場合に CloudEventDecodeError が発生する。"""
        payload: dict[str, object] = {
            "targetDate": "2026-03-05",
            "featureVersion": "v1.0.0",
            "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
        }
        cloud_event = _build_cloud_event(payload=payload)
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="universeCount"):
            decode_pubsub_push_message(message)

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


class TestCloudEventOccurredAtValidation:
    """occurredAt の必須チェックと date-time 形式検証。"""

    def test_missing_occurred_at_raises_error(self) -> None:
        """occurredAt がない場合にエラーを送出する。"""
        cloud_event = _build_cloud_event()
        del cloud_event["occurredAt"]
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="occurredAt"):
            decode_pubsub_push_message(message)

    def test_empty_occurred_at_raises_error(self) -> None:
        """occurredAt が空文字の場合にエラーを送出する。"""
        cloud_event = _build_cloud_event(occurred_at="")
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="occurredAt"):
            decode_pubsub_push_message(message)

    def test_invalid_occurred_at_format_raises_error(self) -> None:
        """occurredAt が ISO8601 date-time でない場合にエラーを送出する。"""
        cloud_event = _build_cloud_event(occurred_at="not-a-datetime")
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="occurredAt"):
            decode_pubsub_push_message(message)

    def test_valid_occurred_at_with_offset(self) -> None:
        """occurredAt がオフセット付き ISO8601 の場合は受け入れる。"""
        cloud_event = _build_cloud_event(occurred_at="2026-03-05T09:00:00+09:00")
        message = _build_pubsub_message(cloud_event)

        result = decode_pubsub_push_message(message)

        assert result.occurred_at == "2026-03-05T09:00:00+09:00"


class TestCloudEventSchemaVersionValidation:
    """schemaVersion の必須チェック。"""

    def test_missing_schema_version_raises_error(self) -> None:
        """schemaVersion がない場合にエラーを送出する。"""
        cloud_event = _build_cloud_event()
        del cloud_event["schemaVersion"]
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="schemaVersion"):
            decode_pubsub_push_message(message)

    def test_empty_schema_version_raises_error(self) -> None:
        """schemaVersion が空文字の場合にエラーを送出する。"""
        cloud_event = _build_cloud_event(schema_version="")
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="schemaVersion"):
            decode_pubsub_push_message(message)


class TestCloudEventUlidValidation:
    """identifier, trace の ULID 形式検証。"""

    def test_non_ulid_identifier_raises_error(self) -> None:
        """identifier が ULID 形式でない場合にエラーを送出する。"""
        cloud_event = _build_cloud_event(identifier="not-a-ulid")
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="identifier"):
            decode_pubsub_push_message(message)

    def test_non_ulid_trace_raises_error(self) -> None:
        """trace が ULID 形式でない場合にエラーを送出する。"""
        cloud_event = _build_cloud_event(trace="not-a-ulid")
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="trace"):
            decode_pubsub_push_message(message)

    def test_lowercase_ulid_raises_error(self) -> None:
        """小文字 ULID は不正形式としてエラーを送出する。"""
        cloud_event = _build_cloud_event(identifier="01jarq0000aaaaaaaaaaaaaaaa")
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="identifier"):
            decode_pubsub_push_message(message)

    def test_ulid_with_excluded_letters_raises_error(self) -> None:
        """ULID で使用されない文字(I, L, O, U)を含む場合はエラー。"""
        cloud_event = _build_cloud_event(identifier="01JARQ0000AAAAAAAAAAAAAAAI")
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="identifier"):
            decode_pubsub_push_message(message)

    def test_valid_ulid_is_accepted(self) -> None:
        """正しい ULID 形式は受け入れられる。"""
        cloud_event = _build_cloud_event(
            identifier="01JARQ0000AAAAAAAAAAAAAAAA",
            trace="01JARQ0000BBBBBBBBBBBBBBBB",
        )
        message = _build_pubsub_message(cloud_event)

        result = decode_pubsub_push_message(message)

        assert result.identifier == "01JARQ0000AAAAAAAAAAAAAAAA"
        assert result.trace == "01JARQ0000BBBBBBBBBBBBBBBB"


class TestUniverseCountRequiredByAsyncApiSchema:
    """AsyncAPI スキーマで universeCount が required に追加されたことの確認テスト。"""

    def test_universe_count_is_accepted_as_integer(self) -> None:
        """universeCount が integer で渡された場合は正常にデコードされる。"""
        payload: dict[str, object] = {
            "targetDate": "2026-03-05",
            "featureVersion": "v1.0.0",
            "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
            "universeCount": 200,
        }
        cloud_event = _build_cloud_event(payload=payload)
        message = _build_pubsub_message(cloud_event)

        result = decode_pubsub_push_message(message)

        assert result.universe_count == 200

    def test_universe_count_absent_raises_error(self) -> None:
        """AsyncAPI スキーマ準拠: universeCount 欠損時にエラーを送出する。"""
        payload: dict[str, object] = {
            "targetDate": "2026-03-05",
            "featureVersion": "v1.0.0",
            "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
        }
        cloud_event = _build_cloud_event(payload=payload)
        message = _build_pubsub_message(cloud_event)

        with pytest.raises(CloudEventDecodeError, match="universeCount"):
            decode_pubsub_push_message(message)


class TestPubsubPushMessageTypeValidation:
    """push_message の型検証 (指摘6)。"""

    def test_non_dict_push_message_raises_error(self) -> None:
        """push_message が dict でない場合にエラーを送出する。"""
        with pytest.raises(CloudEventDecodeError, match="dict"):
            decode_pubsub_push_message([1, 2, 3])  # type: ignore[arg-type]

    def test_string_push_message_raises_error(self) -> None:
        """push_message が文字列の場合にエラーを送出する。"""
        with pytest.raises(CloudEventDecodeError, match="dict"):
            decode_pubsub_push_message("not a dict")  # type: ignore[arg-type]

    def test_none_push_message_raises_error(self) -> None:
        """push_message が None の場合にエラーを送出する。"""
        with pytest.raises(CloudEventDecodeError, match="dict"):
            decode_pubsub_push_message(None)  # type: ignore[arg-type]
