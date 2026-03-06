"""CloudEvents envelope decoder for Pub/Sub push messages.

Pub/Sub push メッセージから CloudEvents JSON エンベロープをデコードし、
features.generated イベントのペイロードを抽出する。
"""

from __future__ import annotations

import base64
import json
import logging
import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta

logger = logging.getLogger(__name__)

_ULID_PATTERN = re.compile(r"^[0-9A-HJKMNP-TV-Z]{26}$")

_EXPECTED_EVENT_TYPE = "features.generated"


class CloudEventDecodeError(Exception):
    """CloudEvents エンベロープのデコードに失敗した場合に送出される例外。"""


@dataclass(frozen=True)
class CloudEventPayload:
    """features.generated イベントからデコードされたペイロード。"""

    identifier: str
    event_type: str
    occurred_at: str
    trace: str
    schema_version: str
    target_date: date
    feature_version: str
    storage_path: str
    universe_count: int


def decode_pubsub_push_message(
    push_message: dict[str, object],
) -> CloudEventPayload:
    """Pub/Sub push メッセージから CloudEventPayload をデコードする。

    Args:
        push_message: Pub/Sub HTTP push エンドポイントに届く JSON ボディ。

    Returns:
        デコード・検証済みの CloudEventPayload。

    Raises:
        CloudEventDecodeError: エンベロープまたはペイロードの構造が不正な場合。
    """
    # Step 0: push_message の型検証
    if not isinstance(push_message, dict):
        raise CloudEventDecodeError(f"push_message must be a dict, got {type(push_message).__name__}")

    # Step 1: Pub/Sub エンベロープの検証
    message = push_message.get("message")
    if not isinstance(message, dict):
        raise CloudEventDecodeError("Pub/Sub envelope missing 'message' key")

    data_encoded = message.get("data")
    if not isinstance(data_encoded, str):
        raise CloudEventDecodeError("Pub/Sub message missing 'data' key")

    # Step 2: Base64 デコード
    try:
        data_bytes = base64.b64decode(data_encoded, validate=True)
    except Exception as error:
        raise CloudEventDecodeError(f"Failed to decode base64 data: {error}") from error

    # Step 3: JSON パース
    try:
        cloud_event = json.loads(data_bytes)
    except json.JSONDecodeError as error:
        raise CloudEventDecodeError(f"Failed to parse JSON from decoded data: {error}") from error

    if not isinstance(cloud_event, dict):
        raise CloudEventDecodeError("Decoded JSON is not an object")

    # Step 4: CloudEvents エンベロープのフィールド検証
    _require_string_field(cloud_event, "identifier")
    _require_ulid_field(cloud_event, "identifier")
    _require_string_field(cloud_event, "trace")
    _require_ulid_field(cloud_event, "trace")
    _require_string_field(cloud_event, "eventType")
    _require_string_field(cloud_event, "occurredAt")
    _require_datetime_field(cloud_event, "occurredAt")
    _require_string_field(cloud_event, "schemaVersion")

    event_type = cloud_event["eventType"]
    if event_type != _EXPECTED_EVENT_TYPE:
        raise CloudEventDecodeError(f"Unexpected eventType: expected '{_EXPECTED_EVENT_TYPE}', got '{event_type}'")

    occurred_at: str = cloud_event["occurredAt"]
    schema_version: str = cloud_event["schemaVersion"]

    # Step 5: payload の検証
    payload = cloud_event.get("payload")
    if not isinstance(payload, dict):
        raise CloudEventDecodeError("CloudEvent missing 'payload' field")

    _require_string_field(payload, "targetDate")
    _require_string_field(payload, "featureVersion")
    _require_string_field(payload, "storagePath")

    # targetDate のパース
    target_date_string = payload["targetDate"]
    try:
        target_date = date.fromisoformat(target_date_string)
    except (ValueError, TypeError) as error:
        raise CloudEventDecodeError(f"Invalid targetDate format: '{target_date_string}'") from error

    # universeCount は必須 (AsyncAPI スキーマ準拠)
    universe_count = _require_integer_field(payload, "universeCount")

    return CloudEventPayload(
        identifier=cloud_event["identifier"],
        event_type=event_type,
        occurred_at=occurred_at,
        trace=cloud_event["trace"],
        schema_version=schema_version,
        target_date=target_date,
        feature_version=payload["featureVersion"],
        storage_path=payload["storagePath"],
        universe_count=universe_count,
    )


def extract_envelope_identifiers(
    push_message: dict[str, object],
) -> tuple[str, str] | None:
    """Pub/Sub push body から identifier と trace をベストエフォートで抽出する。

    デコード失敗時に failed イベントを発行するための部分抽出関数。
    identifier/trace が ULID 形式で取得できる場合のみタプルを返し、
    取得できない場合は None を返す。
    """
    try:
        message = push_message.get("message")
        if not isinstance(message, dict):
            return None
        data_encoded = message.get("data")
        if not isinstance(data_encoded, str):
            return None
        data_bytes = base64.b64decode(data_encoded, validate=True)
        cloud_event = json.loads(data_bytes)
        if not isinstance(cloud_event, dict):
            return None
        identifier = cloud_event.get("identifier")
        trace = cloud_event.get("trace")
        if not isinstance(identifier, str) or not isinstance(trace, str):
            return None
        if not _ULID_PATTERN.match(identifier) or not _ULID_PATTERN.match(trace):
            return None
        return (identifier, trace)
    except Exception:
        return None


def _require_integer_field(data: dict[str, object], field_name: str) -> int:
    """dict に指定のフィールドが存在し、整数であることを検証する。"""
    value = data.get(field_name)
    if not isinstance(value, int):
        raise CloudEventDecodeError(f"Missing or invalid required field: '{field_name}' (expected int)")
    return value


def _require_string_field(data: dict[str, object], field_name: str) -> None:
    """dict に指定のフィールドが存在し、文字列であることを検証する。"""
    value = data.get(field_name)
    if not isinstance(value, str) or not value:
        raise CloudEventDecodeError(f"Missing or empty required field: '{field_name}'")


def _require_ulid_field(data: dict[str, object], field_name: str) -> None:
    """フィールドが ULID 形式 (Crockford Base32, 26文字) であることを検証する。"""
    value = data[field_name]
    assert isinstance(value, str)
    if not _ULID_PATTERN.match(value):
        raise CloudEventDecodeError(f"Invalid ULID format for '{field_name}': '{value}'")


def _require_datetime_field(data: dict[str, object], field_name: str) -> None:
    """フィールドが ISO8601 date-time 形式かつ UTC であることを検証する。

    AsyncAPI EventEnvelope 契約により occurredAt は UTC 必須。
    """
    value = data[field_name]
    assert isinstance(value, str)
    try:
        parsed = datetime.fromisoformat(value)
    except (ValueError, TypeError) as error:
        raise CloudEventDecodeError(f"Invalid date-time format for '{field_name}': '{value}'") from error
    if parsed.tzinfo is None:
        raise CloudEventDecodeError(f"'{field_name}' must be timezone-aware (UTC required): '{value}'")
    if parsed.utcoffset() != timedelta(0):
        raise CloudEventDecodeError(f"'{field_name}' must be UTC (got offset: {parsed.utcoffset()}): '{value}'")
