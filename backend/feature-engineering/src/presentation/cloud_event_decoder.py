"""CloudEvents decoder for Pub/Sub push messages."""

from __future__ import annotations

from collections.abc import Mapping

from alpha_mind_backend_common.messaging.cloud_events import (
    CloudEventDecodeError,
    require_date_field,
    require_mapping_field,
    require_string_field,
)
from alpha_mind_backend_common.messaging.pubsub_push import decode_pubsub_push_envelope
from domain.value_object.enums import SourceStatusValue
from domain.value_object.market_snapshot import MarketSnapshot
from domain.value_object.source_status import SourceStatus

_EXPECTED_EVENT_TYPE = "market.collected"
__all__ = ["CloudEventDecodeError", "decode_pubsub_push_message"]


def decode_pubsub_push_message(
    body: dict[str, object],
) -> tuple[str, MarketSnapshot, str]:
    """Decode a Pub/Sub push message into (identifier, MarketSnapshot, trace)."""
    envelope = decode_pubsub_push_envelope(body, expected_event_type=_EXPECTED_EVENT_TYPE)
    market = _decode_market_snapshot(envelope.payload)

    return envelope.identifier, market, envelope.trace


def _decode_market_snapshot(payload: Mapping[str, object]) -> MarketSnapshot:
    """Decode the payload section into a MarketSnapshot value object."""
    target_date = require_date_field(payload, "targetDate")
    storage_path = require_string_field(payload, "storagePath")
    source_status_data = require_mapping_field(payload, "sourceStatus")

    try:
        source_status = SourceStatus(
            jp=SourceStatusValue(source_status_data.get("jp", "")),
            us=SourceStatusValue(source_status_data.get("us", "")),
        )
    except ValueError as error:
        raise CloudEventDecodeError(f"Invalid 'sourceStatus' value: {error}") from error

    return MarketSnapshot(
        target_date=target_date,
        storage_path=storage_path,
        source_status=source_status,
    )
