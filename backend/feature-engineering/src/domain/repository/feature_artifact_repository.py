"""Repository ABC for feature artifact storage."""

from __future__ import annotations

from abc import ABC, abstractmethod

from domain.value_object.feature_artifact import FeatureArtifact


class FeatureArtifactRepository(ABC):
    """Abstract interface for persisting and retrieving feature artifacts in Cloud Storage."""

    @abstractmethod
    def persist(self, feature_artifact: FeatureArtifact) -> None:
        ...

    @abstractmethod
    def find(self, feature_version: str) -> FeatureArtifact | None:
        ...

    @abstractmethod
    def terminate(self, feature_version: str) -> None:
        ...
