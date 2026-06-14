"""Maps domain events to CloudEvents integration event envelopes."""

from __future__ import annotations

import datetime
from typing import Any

from domain.event.domain_events import HypothesisBacktested, HypothesisPromoted, HypothesisRejected

SCHEMA_VERSION = "1.0.0"


class DomainToIntegrationEventMapper:
    """Stateless mapper from domain events to CloudEvents-compatible envelopes."""

    @staticmethod
    def map(event: HypothesisBacktested | HypothesisPromoted | HypothesisRejected) -> dict[str, Any]:
        if isinstance(event, HypothesisBacktested):
            return _map_backtested(event)
        if isinstance(event, HypothesisPromoted):
            return _map_promoted(event)
        if isinstance(event, HypothesisRejected):
            return _map_rejected(event)
        raise ValueError(f"Unsupported domain event type: {type(event).__name__}")


def _format_utc_iso8601(value: datetime.datetime) -> str:
    """Format a UTC datetime as ISO 8601 with Z suffix (e.g. 2026-01-15T09:00:00Z)."""
    if value.tzinfo is None:
        raise ValueError("occurred_at must be timezone-aware (UTC)")
    return value.astimezone(datetime.UTC).isoformat().replace("+00:00", "Z")


def _map_backtested(event: HypothesisBacktested) -> dict[str, Any]:
    return {
        "identifier": event.identifier,
        "eventType": event.event_type,
        "occurredAt": _format_utc_iso8601(event.occurred_at),
        "trace": event.trace,
        "schemaVersion": SCHEMA_VERSION,
        "payload": {
            "passed": event.passed,
            "costAdjustedReturn": event.cost_adjusted_return,
            "dsr": event.dsr,
            "pbo": event.pbo,
        },
    }


def _map_promoted(event: HypothesisPromoted) -> dict[str, Any]:
    return {
        "identifier": event.identifier,
        "eventType": event.event_type,
        "occurredAt": _format_utc_iso8601(event.occurred_at),
        "trace": event.trace,
        "schemaVersion": SCHEMA_VERSION,
        "payload": {
            "decision": event.decision.value,
            "actionReasonCode": event.action_reason_code,
            "promotionMode": event.promotion_mode.value,
            "mnpiSelfDeclared": event.mnpi_self_declared,
            "insiderRisk": event.insider_risk.value,
        },
    }


def _map_rejected(event: HypothesisRejected) -> dict[str, Any]:
    return {
        "identifier": event.identifier,
        "eventType": event.event_type,
        "occurredAt": _format_utc_iso8601(event.occurred_at),
        "trace": event.trace,
        "schemaVersion": SCHEMA_VERSION,
        "payload": {
            "decision": event.decision.value,
            "actionReasonCode": event.action_reason_code,
            "promotionMode": event.promotion_mode.value,
            "mnpiSelfDeclared": event.mnpi_self_declared,
            "insiderRisk": event.insider_risk.value,
        },
    }
