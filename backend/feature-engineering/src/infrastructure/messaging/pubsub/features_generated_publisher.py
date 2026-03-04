"""Pub/Sub publisher for features.generated events."""

from __future__ import annotations

import json

from google.cloud.pubsub_v1 import PublisherClient

from domain.event.domain_events import FeatureGenerationCompleted
from infrastructure.event_mapping.domain_to_integration_event_mapper import (
    DomainToIntegrationEventMapper,
)


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
            content_type="application/json",
        )
        # Block until the message is delivered
        future.result()
