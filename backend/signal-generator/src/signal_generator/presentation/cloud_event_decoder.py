"""CloudEvents envelope decoder for Pub/Sub push messages."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import date

from alpha_mind_backend_common.messaging.cloud_events import (
    CloudEventDecodeError,
    require_date_field,
    require_integer_field,
    require_string_field,
)
from alpha_mind_backend_common.messaging.pubsub_push import (
    decode_pubsub_push_envelope,
    extract_pubsub_push_identifiers,
)

logger = logging.getLogger(__name__)

_EXPECTED_EVENT_TYPE = "features.generated"


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
    """Pub/Sub push メッセージから CloudEventPayload をデコードする。"""
    if not isinstance(push_message, dict):
        raise CloudEventDecodeError(f"push_message must be a dict, got {type(push_message).__name__}")

    envelope = decode_pubsub_push_envelope(push_message, expected_event_type=_EXPECTED_EVENT_TYPE)

    return CloudEventPayload(
        identifier=envelope.identifier,
        event_type=envelope.event_type,
        occurred_at=envelope.occurred_at,
        trace=envelope.trace,
        schema_version=envelope.schema_version,
        target_date=require_date_field(envelope.payload, "targetDate"),
        feature_version=require_string_field(envelope.payload, "featureVersion"),
        storage_path=require_string_field(envelope.payload, "storagePath"),
        universe_count=require_integer_field(envelope.payload, "universeCount"),
    )


def extract_envelope_identifiers(
    push_message: dict[str, object],
) -> tuple[str, str] | None:
    """Pub/Sub push body から identifier と trace をベストエフォートで抽出する。"""
    if not isinstance(push_message, dict):
        return None
    return extract_pubsub_push_identifiers(push_message)
