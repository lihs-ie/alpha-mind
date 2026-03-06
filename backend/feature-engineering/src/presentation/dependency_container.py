"""Dependency Injection container for feature-engineering service.

Wires all infrastructure implementations to domain/usecase interfaces.
All GCP clients and environment variable reads happen here, keeping
the rest of the application free from direct infrastructure coupling.
"""

from __future__ import annotations

import datetime
import logging
import os
import uuid

from google.cloud import firestore, storage  # type: ignore[attr-defined]
from google.cloud.pubsub_v1 import PublisherClient

from domain.factory.feature_dispatch_factory import FeatureDispatchFactory
from domain.factory.feature_generation_factory import FeatureGenerationFactory
from domain.service.feature_leakage_policy import FeatureLeakagePolicy
from domain.service.feature_version_generator import FeatureVersionGenerator
from domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
from infrastructure.messaging.pubsub.features_generated_publisher import FeaturesGeneratedPublisher
from infrastructure.messaging.pubsub.features_generation_failed_publisher import FeaturesGenerationFailedPublisher
from infrastructure.messaging.pubsub.pubsub_event_publisher import PubSubEventPublisher
from infrastructure.persistence.cloud_storage.cloud_storage_feature_artifact_repository import (
    CloudStorageFeatureArtifactRepository,
)
from infrastructure.persistence.firestore.firestore_feature_dispatch_repository import (
    FirestoreFeatureDispatchRepository,
)
from infrastructure.persistence.firestore.firestore_feature_generation_repository import (
    FirestoreFeatureGenerationRepository,
)
from infrastructure.persistence.firestore.firestore_idempotency_key_repository import (
    FirestoreIdempotencyKeyRepository,
)
from infrastructure.persistence.firestore.firestore_insight_record_repository import (
    FirestoreInsightRecordRepository,
)
from presentation.logging_audit_writer import LoggingFeatureAuditWriter
from usecase.feature_generation_service import FeatureGenerationService

logger = logging.getLogger(__name__)

SERVICE_NAME = "feature-engineering"


class _UlidFeatureVersionGenerator(FeatureVersionGenerator):
    """Simple feature version generator using date prefix + ULID suffix."""

    def generate(self, target_date: datetime.date) -> str:
        return f"v-{target_date.isoformat()}-{uuid.uuid4().hex[:8]}"


class DependencyContainer:
    """Wires infrastructure implementations to domain interfaces.

    All environment variable reads and GCP client instantiation happen in __init__.
    """

    def __init__(self) -> None:
        self._gcp_project_id = _require_env("GCP_PROJECT_ID")
        self._features_generated_topic = _require_env("FEATURES_GENERATED_TOPIC")
        self._features_generation_failed_topic = _require_env("FEATURES_GENERATION_FAILED_TOPIC")
        self._feature_store_bucket = _require_env("FEATURE_STORE_BUCKET")

        self._firestore_client = firestore.Client(project=self._gcp_project_id)
        self._storage_client = storage.Client(project=self._gcp_project_id)
        self._publisher_client = PublisherClient()

        self._feature_generation_service_instance: FeatureGenerationService | None = None

    def feature_generation_service(self) -> FeatureGenerationService:
        """Return a singleton FeatureGenerationService with all dependencies wired."""
        if self._feature_generation_service_instance is not None:
            return self._feature_generation_service_instance

        # Repositories
        idempotency_key_repository = FirestoreIdempotencyKeyRepository(
            client=self._firestore_client,
            service_name=SERVICE_NAME,
        )
        feature_generation_repository = FirestoreFeatureGenerationRepository(
            client=self._firestore_client,
        )
        feature_dispatch_repository = FirestoreFeatureDispatchRepository(
            client=self._firestore_client,
        )
        insight_record_repository = FirestoreInsightRecordRepository(
            client=self._firestore_client,
        )
        feature_artifact_repository = CloudStorageFeatureArtifactRepository(
            client=self._storage_client,
            bucket_name=self._feature_store_bucket,
        )

        # Event publishers
        features_generated_publisher = FeaturesGeneratedPublisher(
            client=self._publisher_client,
            topic_path=self._publisher_client.topic_path(
                self._gcp_project_id,
                self._features_generated_topic,
            ),
        )
        features_generation_failed_publisher = FeaturesGenerationFailedPublisher(
            client=self._publisher_client,
            topic_path=self._publisher_client.topic_path(
                self._gcp_project_id,
                self._features_generation_failed_topic,
            ),
        )
        event_publisher = PubSubEventPublisher(
            features_generated_publisher=features_generated_publisher,
            features_generation_failed_publisher=features_generation_failed_publisher,
        )

        # Domain services and factories
        feature_version_generator = _UlidFeatureVersionGenerator()
        feature_generation_factory = FeatureGenerationFactory(
            feature_version_generator=feature_version_generator,
        )
        feature_dispatch_factory = FeatureDispatchFactory()
        point_in_time_join_policy = PointInTimeJoinPolicy()
        feature_leakage_policy = FeatureLeakagePolicy()

        # Audit writer
        feature_audit_writer = LoggingFeatureAuditWriter()

        self._feature_generation_service_instance = FeatureGenerationService(
            feature_generation_repository=feature_generation_repository,
            feature_dispatch_repository=feature_dispatch_repository,
            feature_artifact_repository=feature_artifact_repository,
            idempotency_key_repository=idempotency_key_repository,
            insight_record_repository=insight_record_repository,
            feature_generation_factory=feature_generation_factory,
            feature_dispatch_factory=feature_dispatch_factory,
            point_in_time_join_policy=point_in_time_join_policy,
            feature_leakage_policy=feature_leakage_policy,
            event_publisher=event_publisher,
            feature_audit_writer=feature_audit_writer,
        )

        return self._feature_generation_service_instance


def _require_env(name: str) -> str:
    """Read a required environment variable or raise EnvironmentError."""
    value = os.environ.get(name)
    if not value:
        raise OSError(f"Required environment variable '{name}' is not set")
    return value
