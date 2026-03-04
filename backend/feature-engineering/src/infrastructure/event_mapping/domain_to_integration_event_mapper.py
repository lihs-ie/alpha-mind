"""Maps domain events to CloudEvents integration event envelopes."""

from __future__ import annotations

from typing import Any

from domain.event.domain_events import FeatureGenerationCompleted, FeatureGenerationFailed

SCHEMA_VERSION = "1.0.0"


class DomainToIntegrationEventMapper:
    """Stateless mapper from domain events to CloudEvents-compatible envelopes."""

    @staticmethod
    def map(event: FeatureGenerationCompleted | FeatureGenerationFailed) -> dict[str, Any]:
        if isinstance(event, FeatureGenerationCompleted):
            return _map_completed(event)
        if isinstance(event, FeatureGenerationFailed):
            return _map_failed(event)
        raise ValueError(f"Unsupported domain event type: {type(event).__name__}")


def _map_completed(event: FeatureGenerationCompleted) -> dict[str, Any]:
    return {
        "identifier": event.identifier,
        "eventType": "features.generated",
        "occurredAt": event.occurred_at.isoformat(),
        "trace": event.trace,
        "schemaVersion": SCHEMA_VERSION,
        "payload": {
            "targetDate": event.target_date.isoformat(),
            "featureVersion": event.feature_version,
            "storagePath": event.storage_path,
        },
    }


def _map_failed(event: FeatureGenerationFailed) -> dict[str, Any]:
    return {
        "identifier": event.identifier,
        "eventType": "features.generation.failed",
        "occurredAt": event.occurred_at.isoformat(),
        "trace": event.trace,
        "schemaVersion": SCHEMA_VERSION,
        "payload": {
            "reasonCode": event.reason_code.value,
            "detail": event.detail,
        },
    }
