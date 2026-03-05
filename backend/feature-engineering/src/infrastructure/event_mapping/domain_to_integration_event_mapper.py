"""Maps domain events to CloudEvents integration event envelopes."""

from __future__ import annotations

import datetime
from typing import Any

from domain.event.domain_events import FeatureGenerationCompleted, FeatureGenerationFailed

SCHEMA_VERSION = "1.0.0"

# Reason codes defined in the AsyncAPI contract (ReasonCode.yaml).
_ASYNCAPI_REASON_CODES: frozenset[str] = frozenset(
    {
        "AUTH_INVALID_CREDENTIALS",
        "AUTH_TOKEN_EXPIRED",
        "AUTH_FORBIDDEN",
        "REQUEST_VALIDATION_FAILED",
        "RESOURCE_NOT_FOUND",
        "STATE_CONFLICT",
        "OPERATION_NOT_ALLOWED",
        "KILL_SWITCH_ENABLED",
        "RISK_LIMIT_EXCEEDED",
        "RISK_EVALUATION_UNAVAILABLE",
        "MODEL_NOT_FOUND",
        "MODEL_NOT_APPROVED",
        "MODEL_DECISION_INVALID",
        "COMPLIANCE_REVIEW_REQUIRED",
        "COMPLIANCE_RESTRICTED_SYMBOL",
        "COMPLIANCE_BLACKOUT_ACTIVE",
        "COMPLIANCE_MNPI_SUSPECTED",
        "COMPLIANCE_SOURCE_UNAPPROVED",
        "DATA_SOURCE_TIMEOUT",
        "DATA_SOURCE_UNAVAILABLE",
        "DATA_SCHEMA_INVALID",
        "DATA_QUALITY_LEAK_DETECTED",
        "FEATURE_GENERATION_FAILED",
        "SIGNAL_GENERATION_FAILED",
        "ORDER_PROPOSAL_FAILED",
        "EXECUTION_BROKER_TIMEOUT",
        "EXECUTION_BROKER_REJECTED",
        "EXECUTION_MARKET_CLOSED",
        "EXECUTION_INSUFFICIENT_FUNDS",
        "AUDIT_WRITE_FAILED",
        "IDEMPOTENCY_DUPLICATE_EVENT",
        "DEPENDENCY_TIMEOUT",
        "DEPENDENCY_UNAVAILABLE",
        "INTERNAL_ERROR",
    }
)


class DomainToIntegrationEventMapper:
    """Stateless mapper from domain events to CloudEvents-compatible envelopes."""

    @staticmethod
    def map(event: FeatureGenerationCompleted | FeatureGenerationFailed) -> dict[str, Any]:
        if isinstance(event, FeatureGenerationCompleted):
            return _map_completed(event)
        if isinstance(event, FeatureGenerationFailed):
            return _map_failed(event)
        raise ValueError(f"Unsupported domain event type: {type(event).__name__}")


def _format_utc_iso8601(value: datetime.datetime) -> str:
    """Format a UTC datetime as ISO 8601 with Z suffix (e.g. 2026-01-15T09:00:00Z)."""
    if value.tzinfo is None:
        raise ValueError("occurred_at must be timezone-aware (UTC)")
    return value.astimezone(datetime.UTC).isoformat().replace("+00:00", "Z")


def _map_completed(event: FeatureGenerationCompleted) -> dict[str, Any]:
    return {
        "identifier": event.identifier,
        "eventType": "features.generated",
        "occurredAt": _format_utc_iso8601(event.occurred_at),
        "trace": event.trace,
        "schemaVersion": SCHEMA_VERSION,
        "payload": {
            "targetDate": event.target_date.isoformat(),
            "featureVersion": event.feature_version,
            "storagePath": event.storage_path,
        },
    }


def _map_failed(event: FeatureGenerationFailed) -> dict[str, Any]:
    reason_code_value = event.reason_code.value
    if reason_code_value not in _ASYNCAPI_REASON_CODES:
        raise ValueError(f"reasonCode '{reason_code_value}' is not defined in AsyncAPI contract")

    return {
        "identifier": event.identifier,
        "eventType": "features.generation.failed",
        "occurredAt": _format_utc_iso8601(event.occurred_at),
        "trace": event.trace,
        "schemaVersion": SCHEMA_VERSION,
        "payload": {
            "reasonCode": reason_code_value,
            "detail": event.detail,
        },
    }
