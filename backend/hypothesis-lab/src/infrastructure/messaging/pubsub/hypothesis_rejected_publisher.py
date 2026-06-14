"""Pub/Sub publisher for hypothesis.rejected events."""

from __future__ import annotations

import json

from google.cloud.pubsub_v1 import PublisherClient

from domain.event.domain_events import HypothesisRejected
from infrastructure.event_mapping.domain_to_integration_event_mapper import (
    DomainToIntegrationEventMapper,
)

SERVICE_SOURCE = "urn:alpha-mind:service:hypothesis-lab"


class HypothesisRejectedPublisher:
    """Publishes HypothesisRejected domain events to Pub/Sub as CloudEvents."""

    def __init__(self, client: PublisherClient, topic_path: str) -> None:
        self._client = client
        self._topic_path = topic_path

    def publish(self, event: HypothesisRejected) -> str:
        """Publish a HypothesisRejected event to Pub/Sub.

        Returns:
            The message ID assigned by Pub/Sub.
        """
        envelope = DomainToIntegrationEventMapper.map(event)
        data = json.dumps(envelope).encode("utf-8")

        future = self._client.publish(
            self._topic_path,
            data=data,
            **{
                "datacontenttype": "application/json",
                "ce-specversion": "1.0",
                "ce-id": envelope["identifier"],
                "ce-type": envelope["eventType"],
                "ce-source": SERVICE_SOURCE,
                "ce-time": envelope["occurredAt"],
            },
        )
        # Block until the message is delivered and return the message ID
        message_id: str = future.result()
        return message_id
