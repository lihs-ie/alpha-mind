"""Pub/Sub publisher for features.generated events."""

from __future__ import annotations

import json

from google.cloud.pubsub_v1 import PublisherClient

from domain.event.domain_events import FeatureGenerationCompleted
from infrastructure.event_mapping.domain_to_integration_event_mapper import (
    DomainToIntegrationEventMapper,
)

SERVICE_SOURCE = "urn:alpha-mind:service:feature-engineering"


class FeaturesGeneratedPublisher:
    """Publishes FeatureGenerationCompleted domain events to Pub/Sub as CloudEvents."""

    def __init__(self, client: PublisherClient, topic_path: str) -> None:
        self._client = client
        self._topic_path = topic_path

    def publish(self, event: FeatureGenerationCompleted) -> None:
        envelope = DomainToIntegrationEventMapper.map(event)
        data = json.dumps(envelope).encode("utf-8")

        future = self._client.publish(
            self._topic_path,
            data=data,
            datacontenttype="application/json",
            ce_specversion="1.0",
            ce_id=envelope["identifier"],
            ce_type=envelope["eventType"],
            ce_source=SERVICE_SOURCE,
            ce_time=envelope["occurredAt"],
        )
        # Block until the message is delivered
        future.result()
