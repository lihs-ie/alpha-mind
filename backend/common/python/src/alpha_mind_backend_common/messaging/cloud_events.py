"""Shared CloudEvents validation helpers."""

from __future__ import annotations

import datetime
import re
from collections.abc import Mapping
from dataclasses import dataclass

_ULID_PATTERN = re.compile(r"^[0-9A-HJKMNP-TV-Z]{26}$")


class CloudEventDecodeError(Exception):
    """Raised when a Pub/Sub push message cannot be decoded as a valid CloudEvent."""


@dataclass(frozen=True)
class CloudEventEnvelope:
    """Normalized CloudEvents envelope."""

    identifier: str
    event_type: str
    occurred_at: str
    trace: str
    schema_version: str
    payload: Mapping[str, object]


def require_string_field(data: Mapping[str, object], field_name: str) -> str:
    """Return a required non-empty string field."""
    value = data.get(field_name)
    if not isinstance(value, str) or not value:
        raise CloudEventDecodeError(f"Missing or invalid required field '{field_name}'")
    return value


def require_integer_field(data: Mapping[str, object], field_name: str) -> int:
    """Return a required integer field."""
    value = data.get(field_name)
    if not isinstance(value, int):
        raise CloudEventDecodeError(f"Missing or invalid required field: '{field_name}' (expected int)")
    return value


def require_mapping_field(data: Mapping[str, object], field_name: str) -> Mapping[str, object]:
    """Return a required mapping field."""
    value = data.get(field_name)
    if not isinstance(value, dict):
        raise CloudEventDecodeError(f"Missing or invalid '{field_name}'")
    return value


def require_date_field(data: Mapping[str, object], field_name: str) -> datetime.date:
    """Return a required ISO8601 date field."""
    value = require_string_field(data, field_name)
    try:
        return datetime.date.fromisoformat(value)
    except ValueError as error:
        raise CloudEventDecodeError(f"Invalid '{field_name}' format: {value}") from error


def require_datetime_field(data: Mapping[str, object], field_name: str) -> str:
    """Return a required timezone-aware ISO8601 datetime string."""
    value = require_string_field(data, field_name)
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = datetime.datetime.fromisoformat(normalized)
    except ValueError as error:
        raise CloudEventDecodeError(f"Invalid date-time format for '{field_name}': '{value}'") from error
    if parsed.tzinfo is None:
        raise CloudEventDecodeError(f"'{field_name}' must be timezone-aware: '{value}'")
    return value


def require_ulid_field(data: Mapping[str, object], field_name: str) -> str:
    """Return a required ULID field."""
    value = require_string_field(data, field_name)
    if not _ULID_PATTERN.fullmatch(value):
        raise CloudEventDecodeError(f"Field '{field_name}' must be a valid ULID (got: '{value}')")
    return value
