"""Feature generation usecase service.

Orchestrates the feature generation workflow following the processing flow
defined in Issue #30. Depends only on domain-layer interfaces (hexagonal architecture).
"""

from __future__ import annotations

import datetime
import logging

from domain.event.domain_events import FeatureGenerationCompleted, FeatureGenerationFailed
from domain.factory.feature_dispatch_factory import FeatureDispatchFactory
from domain.factory.feature_generation_factory import FeatureGenerationFactory
from domain.model.feature_generation import FeatureGeneration
from domain.repository.feature_artifact_repository import FeatureArtifactRepository
from domain.repository.feature_dispatch_repository import FeatureDispatchRepository
from domain.repository.feature_generation_repository import FeatureGenerationRepository
from domain.repository.idempotency_key_repository import IdempotencyKeyRepository
from domain.repository.insight_record_repository import InsightRecordRepository
from domain.service.feature_leakage_policy import FeatureLeakagePolicy
from domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
from domain.value_object.enums import (
    FeatureGenerationStatus,
    PublishedEventType,
    ReasonCode,
)
from domain.value_object.failure_detail import FailureDetail
from domain.value_object.feature_artifact import FeatureArtifact
from domain.value_object.insight_snapshot import InsightSnapshot
from domain.value_object.market_snapshot import MarketSnapshot
from usecase.event_publisher import EventPublisher
from usecase.feature_audit_writer import FeatureAuditWriter

logger = logging.getLogger(__name__)


class FeatureGenerationService:
    """Usecase service that orchestrates feature generation from market.collected events.

    Processing flow (Issue #30):
    1. Idempotency check (RULE-FE-004)
    2. Create FeatureGeneration via factory (RULE-FE-001/002 evaluated)
    3. If already failed, skip to dispatch
    4. Fetch insight records and evaluate leakage (RULE-FE-003)
    5. Build and persist feature artifact (RULE-FE-005)
    6. Complete generation aggregate
    7. Create dispatch, publish event (RULE-FE-007/008)
    8. Persist dispatch, idempotency key, generation
    9. Write audit log
    """

    def __init__(
        self,
        feature_generation_repository: FeatureGenerationRepository,
        feature_dispatch_repository: FeatureDispatchRepository,
        feature_artifact_repository: FeatureArtifactRepository,
        idempotency_key_repository: IdempotencyKeyRepository,
        insight_record_repository: InsightRecordRepository,
        feature_generation_factory: FeatureGenerationFactory,
        feature_dispatch_factory: FeatureDispatchFactory,
        point_in_time_join_policy: PointInTimeJoinPolicy,
        feature_leakage_policy: FeatureLeakagePolicy,
        event_publisher: EventPublisher,
        feature_audit_writer: FeatureAuditWriter,
    ) -> None:
        self._feature_generation_repository = feature_generation_repository
        self._feature_dispatch_repository = feature_dispatch_repository
        self._feature_artifact_repository = feature_artifact_repository
        self._idempotency_key_repository = idempotency_key_repository
        self._insight_record_repository = insight_record_repository
        self._feature_generation_factory = feature_generation_factory
        self._feature_dispatch_factory = feature_dispatch_factory
        self._point_in_time_join_policy = point_in_time_join_policy
        self._feature_leakage_policy = feature_leakage_policy
        self._event_publisher = event_publisher
        self._feature_audit_writer = feature_audit_writer

    def execute(self, identifier: str, market: MarketSnapshot, trace: str) -> None:
        """Execute the feature generation workflow.

        Args:
            identifier: ULID identifying this event (idempotency key).
            market: Normalized market snapshot from market.collected event.
            trace: Trace ID for distributed tracing.
        """
        # Step 1: Idempotency check (RULE-FE-004)
        existing_processed_at = self._idempotency_key_repository.find(identifier)
        if existing_processed_at is not None:
            self._feature_audit_writer.write_duplicate(identifier=identifier, trace=trace)
            return

        # Step 2: Create FeatureGeneration via factory (RULE-FE-001/002 evaluated inside)
        generation = self._feature_generation_factory.from_market_collected_event(
            identifier=identifier,
            market=market,
            trace=trace,
        )

        # Step 3: If factory already failed it (validation/source health), skip to dispatch
        if generation.status != FeatureGenerationStatus.FAILED:
            self._process_feature_generation(generation)

        # Steps 9-14: Dispatch, persist, and audit
        self._dispatch_and_finalize(generation)

    def _process_feature_generation(self, generation: FeatureGeneration) -> None:
        """Steps 4-8: Insight check, leakage detection, artifact creation, completion."""
        target_date = generation.market.target_date
        now = datetime.datetime.now(tz=datetime.UTC)

        # Step 4: Fetch insight records
        insight_snapshot = self._insight_record_repository.find_by_target_date(target_date)

        if insight_snapshot is None:
            # No insight data available - proceed with empty insight
            insight_snapshot = InsightSnapshot(
                record_count=0,
                latest_collected_at=None,
                filtered_by_target_date=True,
            )

        # Step 5: Evaluate feature leakage (RULE-FE-003)
        leakage_result = self._feature_leakage_policy.evaluate(target_date, insight_snapshot)
        if leakage_result.leakage_detected:
            generation.fail(
                failure_detail=FailureDetail(
                    reason_code=ReasonCode.DATA_QUALITY_LEAK_DETECTED,
                    detail="RULE-FE-003: feature leakage detected in insight data",
                    retryable=False,
                ),
                processed_at=now,
            )
            return

        # Step 6: Build feature artifact
        feature_version = self._feature_generation_factory.generate_feature_version(target_date)
        feature_artifact = FeatureArtifact(
            feature_version=feature_version,
            storage_path=f"gs://feature_store/{feature_version}/features.parquet",
            row_count=0,
            feature_count=0,
        )

        # Step 7: Persist artifact (RULE-FE-005: must persist before event publish)
        self._feature_artifact_repository.persist(feature_artifact)

        # Step 8: Complete generation (RULE-FE-005: complete after storage)
        generation.complete(
            feature_artifact=feature_artifact,
            insight=insight_snapshot,
            processed_at=now,
        )

    def _dispatch_and_finalize(self, generation: FeatureGeneration) -> None:
        """Steps 9-14: Create dispatch, publish event, persist everything, write audit."""
        now = datetime.datetime.now(tz=datetime.UTC)

        # Step 9: Create dispatch aggregate from terminal generation
        dispatch = self._feature_dispatch_factory.from_feature_generation(generation)

        # Step 10: Publish integration event
        try:
            if generation.status == FeatureGenerationStatus.GENERATED:
                completed_event = self._find_completed_event(generation)
                if completed_event is not None:
                    self._event_publisher.publish_features_generated(completed_event)
                    dispatch.publish(
                        published_event=PublishedEventType.FEATURES_GENERATED,
                        processed_at=now,
                    )
            elif generation.status == FeatureGenerationStatus.FAILED:
                failed_event = self._find_failed_event(generation)
                if failed_event is not None:
                    self._event_publisher.publish_features_generation_failed(failed_event)
                    dispatch.publish(
                        published_event=PublishedEventType.FEATURES_GENERATION_FAILED,
                        processed_at=now,
                    )
        except Exception:
            logger.exception("Failed to publish integration event for identifier=%s", generation.identifier)
            dispatch.fail(
                reason_code=ReasonCode.DISPATCH_FAILED,
                processed_at=now,
            )

        # Step 11: Persist dispatch
        self._feature_dispatch_repository.persist(dispatch)

        # Step 12: Persist idempotency key
        self._idempotency_key_repository.persist(
            identifier=generation.identifier,
            processed_at=now,
            trace=generation.trace,
        )

        # Step 13: Persist generation
        self._feature_generation_repository.persist(generation)

        # Step 14: Write audit log
        if generation.status == FeatureGenerationStatus.GENERATED:
            assert generation.feature_artifact is not None
            self._feature_audit_writer.write_success(
                identifier=generation.identifier,
                trace=generation.trace,
                target_date=generation.market.target_date,
                feature_version=generation.feature_artifact.feature_version,
            )
        elif generation.status == FeatureGenerationStatus.FAILED:
            assert generation.failure_detail is not None
            self._feature_audit_writer.write_failure(
                identifier=generation.identifier,
                trace=generation.trace,
                reason_code=generation.failure_detail.reason_code,
                detail=generation.failure_detail.detail,
            )

    def _find_completed_event(self, generation: FeatureGeneration) -> FeatureGenerationCompleted | None:
        """Extract the FeatureGenerationCompleted event from domain events."""
        for event in generation.domain_events:
            if isinstance(event, FeatureGenerationCompleted):
                return event
        return None

    def _find_failed_event(self, generation: FeatureGeneration) -> FeatureGenerationFailed | None:
        """Extract the FeatureGenerationFailed event from domain events."""
        for event in generation.domain_events:
            if isinstance(event, FeatureGenerationFailed):
                return event
        return None
