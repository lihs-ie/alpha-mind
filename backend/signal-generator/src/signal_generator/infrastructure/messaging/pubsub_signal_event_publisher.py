"""Pub/Sub publisher for signal events."""

import json

from google.cloud.pubsub_v1 import PublisherClient

from signal_generator.domain.events.signal_generation_completed_event import (
    SignalGenerationCompletedEvent,
)
from signal_generator.domain.events.signal_generation_failed_event import (
    SignalGenerationFailedEvent,
)

_SCHEMA_VERSION = "1.0"
_TOPIC_SIGNAL_GENERATED = "signal.generated"
_TOPIC_SIGNAL_GENERATION_FAILED = "signal.generation.failed"


class PubSubSignalEventPublisher:
    """signal.generated / signal.generation.failed イベントを Pub/Sub に発行する。

    CloudEvents エンベロープでメッセージを構築する。
    """

    def __init__(
        self,
        publisher_client: PublisherClient,
        project_id: str,
    ) -> None:
        self._publisher_client = publisher_client
        self._project_id = project_id

    def publish_signal_generated(
        self, event: SignalGenerationCompletedEvent
    ) -> str:
        """signal.generated イベントを発行し、メッセージ ID を返す。"""
        topic_path = self._build_topic_path(_TOPIC_SIGNAL_GENERATED)
        envelope = _build_signal_generated_envelope(event)
        future = self._publisher_client.publish(
            topic_path, data=json.dumps(envelope).encode("utf-8")
        )
        return future.result()

    def publish_signal_generation_failed(
        self, event: SignalGenerationFailedEvent
    ) -> str:
        """signal.generation.failed イベントを発行し、メッセージ ID を返す。"""
        topic_path = self._build_topic_path(_TOPIC_SIGNAL_GENERATION_FAILED)
        envelope = _build_signal_generation_failed_envelope(event)
        future = self._publisher_client.publish(
            topic_path, data=json.dumps(envelope).encode("utf-8")
        )
        return future.result()

    def _build_topic_path(self, topic_name: str) -> str:
        return f"projects/{self._project_id}/topics/{topic_name}"


def _build_signal_generated_envelope(
    event: SignalGenerationCompletedEvent,
) -> dict:
    """SignalGenerationCompletedEvent から CloudEvents エンベロープを構築する。"""
    return {
        "identifier": event.identifier,
        "eventType": _TOPIC_SIGNAL_GENERATED,
        "occurredAt": event.occurred_at.isoformat(),
        "trace": event.trace,
        "schemaVersion": _SCHEMA_VERSION,
        "payload": {
            "signalVersion": event.signal_version,
            "modelVersion": event.model_version,
            "featureVersion": event.feature_version,
            "storagePath": event.storage_path,
            "modelDiagnostics": {
                "degradationFlag": event.model_diagnostics.degradation_flag.value,
                "requiresComplianceReview": event.model_diagnostics.requires_compliance_review,
                "costAdjustedReturn": event.model_diagnostics.cost_adjusted_return,
                "slippageAdjustedSharpe": event.model_diagnostics.slippage_adjusted_sharpe,
            },
        },
    }


def _build_signal_generation_failed_envelope(
    event: SignalGenerationFailedEvent,
) -> dict:
    """SignalGenerationFailedEvent から CloudEvents エンベロープを構築する。"""
    return {
        "identifier": event.identifier,
        "eventType": _TOPIC_SIGNAL_GENERATION_FAILED,
        "occurredAt": event.occurred_at.isoformat(),
        "trace": event.trace,
        "schemaVersion": _SCHEMA_VERSION,
        "payload": {
            "reasonCode": event.reason_code.value,
            "detail": event.detail,
        },
    }
