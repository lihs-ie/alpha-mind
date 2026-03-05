"""Composite EventPublisher implementation using Pub/Sub publishers.

Delegates to FeaturesGeneratedPublisher and FeaturesGenerationFailedPublisher
for publishing integration events to their respective Pub/Sub topics.
"""

from __future__ import annotations

from typing import Protocol

from domain.event.domain_events import FeatureGenerationCompleted, FeatureGenerationFailed
from usecase.event_publisher import EventPublisher


class _FeaturesGeneratedPublisherProtocol(Protocol):
    def publish(self, event: FeatureGenerationCompleted) -> str: ...


class _FeaturesGenerationFailedPublisherProtocol(Protocol):
    def publish(self, event: FeatureGenerationFailed) -> str: ...


class PubSubEventPublisher(EventPublisher):
    """Composite EventPublisher that delegates to topic-specific publishers."""

    def __init__(
        self,
        features_generated_publisher: _FeaturesGeneratedPublisherProtocol,
        features_generation_failed_publisher: _FeaturesGenerationFailedPublisherProtocol,
    ) -> None:
        self._features_generated_publisher = features_generated_publisher
        self._features_generation_failed_publisher = features_generation_failed_publisher

    def publish_features_generated(self, event: FeatureGenerationCompleted) -> str:
        """Publish a features.generated integration event.

        Returns:
            The message ID assigned by the messaging infrastructure.
        """
        return self._features_generated_publisher.publish(event)

    def publish_features_generation_failed(self, event: FeatureGenerationFailed) -> str:
        """Publish a features.generation.failed integration event.

        Returns:
            The message ID assigned by the messaging infrastructure.
        """
        return self._features_generation_failed_publisher.publish(event)
