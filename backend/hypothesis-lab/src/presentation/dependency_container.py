"""Dependency Injection container for hypothesis-lab service.

Wires all infrastructure implementations to domain/application interfaces.
All GCP clients and environment variable reads happen here, keeping
the rest of the application free from direct infrastructure coupling.
"""

from __future__ import annotations

import datetime
import logging
import os

from google.cloud.firestore_v1 import Client as FirestoreClient
from google.cloud.pubsub_v1 import PublisherClient

from alpha_mind_backend_common.runtime.env import require_env
from application.hypothesis_workflow_service import HypothesisWorkflowService
from domain.factory.hypothesis_factory import HypothesisFactory
from domain.service.promotion_eligibility_policy import PromotionEligibilityPolicy
from domain.specification.promotion_ready_specification import PromotionReadySpecification
from infrastructure.messaging.pubsub.hypothesis_backtested_publisher import HypothesisBacktestedPublisher
from infrastructure.messaging.pubsub.hypothesis_promoted_publisher import HypothesisPromotedPublisher
from infrastructure.messaging.pubsub.hypothesis_rejected_publisher import HypothesisRejectedPublisher
from infrastructure.persistence.firestore.firestore_failure_knowledge_repository import (
    FirestoreFailureKnowledgeRepository,
)
from infrastructure.persistence.firestore.firestore_hypothesis_repository import FirestoreHypothesisRepository
from infrastructure.persistence.firestore.firestore_idempotency_key_repository import (
    FirestoreIdempotencyKeyRepository,
)
from infrastructure.persistence.firestore.firestore_validation_run_repository import (
    FirestoreValidationRunRepository,
)

logger = logging.getLogger(__name__)

SERVICE_NAME = "hypothesis-lab"


class DependencyContainer:
    """Wires infrastructure implementations to domain interfaces.

    All environment variable reads and GCP client instantiation happen in __init__.
    """

    def __init__(self) -> None:
        self._gcp_project_id = require_env("GCP_PROJECT_ID")
        self._hypothesis_backtested_topic = require_env("HYPOTHESIS_BACKTESTED_TOPIC")
        self._hypothesis_promoted_topic = require_env("HYPOTHESIS_PROMOTED_TOPIC")
        self._hypothesis_rejected_topic = require_env("HYPOTHESIS_REJECTED_TOPIC")

        partner_symbols_raw = os.environ.get("PARTNER_RESTRICTED_SYMBOLS", "")
        self._partner_restricted_symbols = [
            symbol.strip() for symbol in partner_symbols_raw.split(",") if symbol.strip()
        ]

        self._firestore_client = FirestoreClient(project=self._gcp_project_id)
        self._publisher_client = PublisherClient()

        self._hypothesis_workflow_service_instance: HypothesisWorkflowService | None = None

    def hypothesis_workflow_service(self) -> HypothesisWorkflowService:
        """Return a singleton HypothesisWorkflowService with all dependencies wired."""
        if self._hypothesis_workflow_service_instance is not None:
            return self._hypothesis_workflow_service_instance

        # Repositories
        hypothesis_repository = FirestoreHypothesisRepository(client=self._firestore_client)
        validation_run_repository = FirestoreValidationRunRepository(client=self._firestore_client)
        failure_knowledge_repository = FirestoreFailureKnowledgeRepository(client=self._firestore_client)
        idempotency_key_repository = FirestoreIdempotencyKeyRepository(
            client=self._firestore_client,
            service_name=SERVICE_NAME,
        )

        # Event publishers
        backtested_publisher = HypothesisBacktestedPublisher(
            client=self._publisher_client,
            topic_path=self._publisher_client.topic_path(
                self._gcp_project_id,
                self._hypothesis_backtested_topic,
            ),
        )
        promoted_publisher = HypothesisPromotedPublisher(
            client=self._publisher_client,
            topic_path=self._publisher_client.topic_path(
                self._gcp_project_id,
                self._hypothesis_promoted_topic,
            ),
        )
        rejected_publisher = HypothesisRejectedPublisher(
            client=self._publisher_client,
            topic_path=self._publisher_client.topic_path(
                self._gcp_project_id,
                self._hypothesis_rejected_topic,
            ),
        )

        # Domain services and factories
        hypothesis_factory = HypothesisFactory()
        promotion_eligibility_policy = PromotionEligibilityPolicy()
        promotion_ready_specification = PromotionReadySpecification()

        self._hypothesis_workflow_service_instance = HypothesisWorkflowService(
            hypothesis_repository=hypothesis_repository,
            validation_run_repository=validation_run_repository,
            failure_knowledge_repository=failure_knowledge_repository,
            idempotency_key_repository=idempotency_key_repository,
            hypothesis_backtested_publisher=backtested_publisher,
            hypothesis_promoted_publisher=promoted_publisher,
            hypothesis_rejected_publisher=rejected_publisher,
            hypothesis_factory=hypothesis_factory,
            promotion_eligibility_policy=promotion_eligibility_policy,
            promotion_ready_specification=promotion_ready_specification,
            partner_restricted_symbols=self._partner_restricted_symbols,
            clock=lambda: datetime.datetime.now(datetime.UTC),
        )

        return self._hypothesis_workflow_service_instance
