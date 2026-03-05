"""Port (ABC) for publishing integration events from the usecase layer."""

from abc import ABC, abstractmethod

from domain.event.domain_events import FeatureGenerationCompleted, FeatureGenerationFailed


class EventPublisher(ABC):
    """Abstract interface for publishing integration events to the event bus."""

    @abstractmethod
    def publish_features_generated(self, event: FeatureGenerationCompleted) -> str:
        """Publish a features.generated integration event.

        Returns:
            The message ID assigned by the messaging infrastructure.
        """
        ...

    @abstractmethod
    def publish_features_generation_failed(self, event: FeatureGenerationFailed) -> str:
        """Publish a features.generation.failed integration event.

        Returns:
            The message ID assigned by the messaging infrastructure.
        """
        ...
