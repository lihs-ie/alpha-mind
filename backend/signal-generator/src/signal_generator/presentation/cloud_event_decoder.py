"""CloudEvents envelope decoder for Pub/Sub push messages.

Pub/Sub push メッセージから CloudEvents JSON エンベロープをデコードし、
features.generated イベントのペイロードを抽出する。
"""

from __future__ import annotations

import base64
import json
import logging
from dataclasses import dataclass
from datetime import date

logger = logging.getLogger(__name__)

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
    universe_count: int | None


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
        raise CloudEventDecodeError(
            f"Failed to decode base64 data: {error}"
        ) from error

    # Step 3: JSON パース
    try:
        cloud_event = json.loads(data_bytes)
    except json.JSONDecodeError as error:
        raise CloudEventDecodeError(
            f"Failed to parse JSON from decoded data: {error}"
        ) from error

    if not isinstance(cloud_event, dict):
        raise CloudEventDecodeError("Decoded JSON is not an object")

    # Step 4: CloudEvents エンベロープのフィールド検証
    _require_string_field(cloud_event, "identifier")
    _require_string_field(cloud_event, "trace")
    _require_string_field(cloud_event, "eventType")

    event_type = cloud_event["eventType"]
    if event_type != _EXPECTED_EVENT_TYPE:
        raise CloudEventDecodeError(
            f"Unexpected eventType: expected '{_EXPECTED_EVENT_TYPE}', got '{event_type}'"
        )

    occurred_at = cloud_event.get("occurredAt", "")
    schema_version = cloud_event.get("schemaVersion", "")

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
        raise CloudEventDecodeError(
            f"Invalid targetDate format: '{target_date_string}'"
        ) from error

    # universeCount はオプション
    universe_count_raw = payload.get("universeCount")
    universe_count: int | None = None
    if universe_count_raw is not None:
        if isinstance(universe_count_raw, int):
            universe_count = universe_count_raw
        else:
            raise CloudEventDecodeError(
                f"Invalid universeCount type: expected int, got {type(universe_count_raw).__name__}"
            )

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


def _require_string_field(data: dict[str, object], field_name: str) -> None:
    """dict に指定のフィールドが存在し、文字列であることを検証する。"""
    value = data.get(field_name)
    if not isinstance(value, str) or not value:
        raise CloudEventDecodeError(f"Missing or empty required field: '{field_name}'")
