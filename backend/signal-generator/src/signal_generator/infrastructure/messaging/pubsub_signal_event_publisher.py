"""Pub/Sub publisher for signal events."""

import datetime
import json
import re
from typing import Any

from google.cloud.pubsub_v1 import PublisherClient

from signal_generator.domain.events.signal_generation_completed_event import (
    SignalGenerationCompletedEvent,
)
from signal_generator.domain.events.signal_generation_failed_event import (
    SignalGenerationFailedEvent,
)
from signal_generator.domain.ports.event_publisher import SignalEventPublisher
from signal_generator.infrastructure.retry import with_retry

_SCHEMA_VERSION = "1.0.0"
_EVENT_TYPE_SIGNAL_GENERATED = "signal.generated"
_EVENT_TYPE_SIGNAL_GENERATION_FAILED = "signal.generation.failed"
_TOPIC_SIGNAL_GENERATED = "event-signal-generated-v1"
_TOPIC_SIGNAL_GENERATION_FAILED = "event-signal-generation-failed-v1"
_ULID_PATTERN = re.compile(r"^[0-9A-HJKMNP-TV-Z]{26}$")


def _validate_envelope_inputs(identifier: str, trace: str, occurred_at: datetime.datetime) -> None:
    """AsyncAPI EventEnvelope 契約に基づく事前検証。"""
    if not _ULID_PATTERN.fullmatch(identifier):
        raise ValueError(f"identifier must be a valid ULID (got: {identifier})")
    if not _ULID_PATTERN.fullmatch(trace):
        raise ValueError(f"trace must be a valid ULID (got: {trace})")
    if occurred_at.tzinfo is None:
        raise ValueError("occurredAt must be timezone-aware")


class PubSubSignalEventPublisher(SignalEventPublisher):
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

    def publish_signal_generated(self, event: SignalGenerationCompletedEvent) -> str:
        """signal.generated イベントを発行し、メッセージ ID を返す。"""
        topic_path = self._build_topic_path(_TOPIC_SIGNAL_GENERATED)
        envelope = _build_signal_generated_envelope(event)
        data = json.dumps(envelope).encode("utf-8")
        return with_retry(lambda: str(self._publisher_client.publish(topic_path, data=data).result()))

    def publish_signal_generation_failed(self, event: SignalGenerationFailedEvent) -> str:
        """signal.generation.failed イベントを発行し、メッセージ ID を返す。"""
        topic_path = self._build_topic_path(_TOPIC_SIGNAL_GENERATION_FAILED)
        envelope = _build_signal_generation_failed_envelope(event)
        data = json.dumps(envelope).encode("utf-8")
        return with_retry(lambda: str(self._publisher_client.publish(topic_path, data=data).result()))

    def _build_topic_path(self, topic_name: str) -> str:
        return f"projects/{self._project_id}/topics/{topic_name}"


def _build_signal_generated_envelope(
    event: SignalGenerationCompletedEvent,
) -> dict[str, Any]:
    """SignalGenerationCompletedEvent から CloudEvents エンベロープを構築する。"""
    _validate_envelope_inputs(event.identifier, event.trace, event.occurred_at)
    return {
        "identifier": event.identifier,
        "eventType": _EVENT_TYPE_SIGNAL_GENERATED,
        "occurredAt": event.occurred_at.isoformat(),
        "trace": event.trace,
        "schemaVersion": _SCHEMA_VERSION,
        "payload": {
            "signalVersion": event.signal_version,
            "modelVersion": event.model_version,
            "featureVersion": event.feature_version,
            "storagePath": event.storage_path,
            "modelDiagnostics": _build_model_diagnostics(event),
        },
    }


def _build_signal_generation_failed_envelope(
    event: SignalGenerationFailedEvent,
) -> dict[str, Any]:
    """SignalGenerationFailedEvent から CloudEvents エンベロープを構築する。"""
    _validate_envelope_inputs(event.identifier, event.trace, event.occurred_at)
    return {
        "identifier": event.identifier,
        "eventType": _EVENT_TYPE_SIGNAL_GENERATION_FAILED,
        "occurredAt": event.occurred_at.isoformat(),
        "trace": event.trace,
        "schemaVersion": _SCHEMA_VERSION,
        "payload": _build_failed_payload(event),
    }


def _build_model_diagnostics(event: SignalGenerationCompletedEvent) -> dict[str, Any]:
    """ModelDiagnostics を構築する。None のフィールドはキー自体を省略する。"""
    diagnostics: dict[str, Any] = {
        "degradationFlag": event.model_diagnostics.degradation_flag.value,
        "requiresComplianceReview": event.model_diagnostics.requires_compliance_review,
    }
    if event.model_diagnostics.cost_adjusted_return is not None:
        diagnostics["costAdjustedReturn"] = event.model_diagnostics.cost_adjusted_return
    if event.model_diagnostics.slippage_adjusted_sharpe is not None:
        diagnostics["slippageAdjustedSharpe"] = event.model_diagnostics.slippage_adjusted_sharpe
    return diagnostics


_DETAIL_MAX_LENGTH = 500


def _build_failed_payload(event: SignalGenerationFailedEvent) -> dict[str, Any]:
    """FailedPayload を構築する。None のフィールドはキー自体を省略する。"""
    payload: dict[str, Any] = {"reasonCode": event.reason_code.value}
    if event.detail is not None:
        payload["detail"] = event.detail[:_DETAIL_MAX_LENGTH]
    return payload
