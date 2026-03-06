"""Feature generation usecase service.

Orchestrates the feature generation workflow following the processing flow
defined in Issue #30 (steps 1-13). Depends only on domain-layer interfaces
(hexagonal architecture).
"""

from __future__ import annotations

import datetime
import logging

from domain.event.domain_events import FeatureGenerationCompleted, FeatureGenerationFailed
from domain.factory.feature_dispatch_factory import FeatureDispatchFactory
from domain.factory.feature_generation_factory import FeatureGenerationFactory
from domain.model.feature_dispatch import FeatureDispatch
from domain.model.feature_generation import FeatureGeneration
from domain.repository.feature_artifact_repository import FeatureArtifactRepository
from domain.repository.feature_dispatch_repository import FeatureDispatchRepository
from domain.repository.feature_generation_repository import FeatureGenerationRepository
from domain.repository.idempotency_key_repository import IdempotencyKeyRepository, ReservationStatus
from domain.repository.insight_record_repository import InsightRecordRepository
from domain.service.feature_leakage_policy import FeatureLeakagePolicy
from domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
from domain.value_object.enums import (
    DispatchStatus,
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


class RetryableFeatureGenerationError(Exception):
    """Raised when feature generation fails with a retryable condition.

    The presentation layer should translate this into an HTTP 500 response
    so that Pub/Sub redelivers the message for retry.
    """


class FeatureGenerationService:
    """Usecase service that orchestrates feature generation from market.collected events.

    Processing flow (Issue #30, steps 1-13):
     1. IdempotencyKeyRepository.reserve(identifier) — atomic duplicate check (RULE-FE-004)
     1b. FeatureDispatchRepository.find(identifier) — partial-failure guard (PUBLISHED only)
     2. FeatureGenerationFactory.from_market_collected_event — create aggregate (RULE-FE-001/002)
     3. If status == FAILED, skip preprocessing (steps 4-8) and proceed to dispatch (steps 9-13)
     4. InsightRecordRepository.find_by_target_date — fetch insight
     5. FeatureLeakagePolicy.evaluate — future-info check (RULE-FE-003)
     6. PointInTimeJoinPolicy.evaluate — temporal consistency check
     7. Feature calculation + FeatureArtifactRepository.persist (RULE-FE-005)
     8. FeatureGeneration.complete() or .fail() — finalise aggregate state
     9. FeatureDispatchFactory.from_feature_generation — create dispatch
    10. EventPublisher.publish — publish integration event (RULE-FE-007/008)
    11. FeatureDispatch.publish + FeatureDispatchRepository.persist — record dispatch
    12. FeatureGenerationRepository.persist — persist generation state
    13. IdempotencyKeyRepository.persist + audit log (idempotency key only on successful dispatch)
        If dispatch fails, the reservation is released to allow retry.
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
        storage_path_prefix: str = "features",
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
        self._storage_path_prefix = storage_path_prefix.rstrip("/")

    def execute(self, identifier: str, market: MarketSnapshot, trace: str) -> None:
        """Execute the feature generation workflow.

        Args:
            identifier: ULID identifying this event (idempotency key).
            market: Normalized market snapshot from market.collected event.
            trace: Trace ID for distributed tracing.
        """
        # Step 1: Atomic idempotency reservation (RULE-FE-004).
        # reserve() atomically checks and claims the identifier, preventing
        # concurrent duplicate processing under parallel consumer/redelivery.
        leased_at = datetime.datetime.now(tz=datetime.UTC)
        lease_expires_at = leased_at + datetime.timedelta(minutes=5)
        reservation = self._idempotency_key_repository.reserve(
            identifier=identifier,
            leased_at=leased_at,
            lease_expires_at=lease_expires_at,
            trace=trace,
        )
        if reservation != ReservationStatus.ACQUIRED:
            self._feature_audit_writer.write_duplicate(identifier=identifier, trace=trace)
            return

        # All processing after reserve() is wrapped in try/finally to guarantee
        # the reservation is always finalized — either persisted or terminated —
        # even when an unexpected error occurs at any step.
        try:
            self._process_after_reservation(identifier, market, trace)
        except RetryableFeatureGenerationError:
            # Idempotency key already terminated in _dispatch_and_finalize.
            # Re-raise so the presentation layer returns 500 for Pub/Sub retry.
            raise
        except Exception:
            logger.exception(
                "Unhandled error after reservation; releasing reservation for identifier=%s",
                identifier,
            )
            try:
                self._idempotency_key_repository.terminate(identifier)
            except Exception:
                logger.exception(
                    "Failed to terminate reservation for identifier=%s",
                    identifier,
                )
            raise

    def _process_after_reservation(self, identifier: str, market: MarketSnapshot, trace: str) -> None:
        """Steps 1b-13: All processing that occurs after the idempotency reservation."""
        # Step 1b: Guard against re-publishing after partial failure.
        # If a previous attempt published an event but crashed before persisting
        # the idempotency key, the dispatch record with PUBLISHED status serves
        # as a secondary guard. FAILED dispatches are allowed to re-process.
        existing_dispatch = self._feature_dispatch_repository.find(identifier)
        if existing_dispatch is not None and existing_dispatch.dispatch_status == DispatchStatus.PUBLISHED:
            # Verify generation record exists — if missing (dispatch persisted but
            # generation persist crashed), raise so Pub/Sub redelivery can retry.
            existing_generation = self._feature_generation_repository.find(identifier)
            if existing_generation is None:
                logger.error(
                    "Published dispatch exists but generation record missing for identifier=%s",
                    identifier,
                )
                # Raise to trigger execute()'s except block which will terminate
                # the reservation and re-raise for Pub/Sub redelivery.
                raise RuntimeError(f"Inconsistent state: dispatch=PUBLISHED but generation missing for {identifier}")
            logger.warning(
                "Published dispatch already exists for identifier=%s; skipping re-processing",
                identifier,
            )
            # Finalize the reservation so it is not left dangling.
            self._idempotency_key_repository.persist(
                identifier=identifier,
                processed_at=datetime.datetime.now(tz=datetime.UTC),
                trace=trace,
            )
            self._feature_audit_writer.write_duplicate(identifier=identifier, trace=trace)
            return

        # Step 1c: Dispatch-only retry — if a FAILED dispatch exists and the
        # generation was already completed (GENERATED), reuse the persisted
        # generation state to avoid re-generating featureVersion (RULE-FE-006).
        if existing_dispatch is not None and existing_dispatch.dispatch_status == DispatchStatus.FAILED:
            existing_generation = self._feature_generation_repository.find(identifier)
            if existing_generation is not None and existing_generation.status == FeatureGenerationStatus.GENERATED:
                logger.info(
                    "Dispatch-only retry: reusing GENERATED generation for identifier=%s",
                    identifier,
                )
                self._dispatch_and_finalize(existing_generation)
                return

        # Step 2: Create FeatureGeneration via factory (RULE-FE-001/002 evaluated inside)
        generation = self._feature_generation_factory.from_market_collected_event(
            identifier=identifier,
            market=market,
            trace=trace,
        )

        # Step 3: If factory already failed it, skip preprocessing and proceed to dispatch
        if generation.status != FeatureGenerationStatus.FAILED:
            try:
                self._process_feature_generation(generation)
            except (ConnectionError, TimeoutError, OSError) as error:
                logger.exception(
                    "Recoverable processing error; identifier=%s",
                    identifier,
                )
                generation.fail(
                    failure_detail=FailureDetail(
                        reason_code=ReasonCode.FEATURE_GENERATION_FAILED,
                        detail=f"Recoverable processing error: {error}",
                        retryable=True,
                    ),
                    processed_at=datetime.datetime.now(tz=datetime.UTC),
                )
            except Exception as error:
                # Includes Google API errors (google.api_core.exceptions.*) which
                # are not caught above but are typically transient. Marking as
                # retryable=True so Pub/Sub redelivery can retry the message.
                logger.exception(
                    "Unexpected error during feature generation processing; identifier=%s",
                    identifier,
                )
                generation.fail(
                    failure_detail=FailureDetail(
                        reason_code=ReasonCode.FEATURE_GENERATION_FAILED,
                        detail=f"Unexpected processing error: {type(error).__name__}: {error}",
                        retryable=True,
                    ),
                    processed_at=datetime.datetime.now(tz=datetime.UTC),
                )

        # Steps 9-13: Dispatch, persist, and audit
        self._dispatch_and_finalize(generation)

        # After dispatch, if the failure is retryable, re-raise so the
        # presentation layer returns 500 and Pub/Sub retries the message.
        if generation.failure_detail is not None and generation.failure_detail.retryable:
            raise RetryableFeatureGenerationError(
                generation.failure_detail.detail or generation.failure_detail.reason_code.value
            )

    def _process_feature_generation(self, generation: FeatureGeneration) -> None:
        """Steps 4-8: Insight check, leakage detection, join validation, artifact creation."""
        target_date = generation.market.target_date
        now = datetime.datetime.now(tz=datetime.UTC)

        # Step 4: Fetch insight records
        insight_snapshot = self._insight_record_repository.find_by_target_date(target_date)

        if insight_snapshot is None:
            insight_snapshot = InsightSnapshot(
                record_count=0,
                latest_collected_at=None,
                filtered_by_target_date=True,
            )

        # Step 5: Evaluate feature leakage (RULE-FE-003)
        leakage_result = self._feature_leakage_policy.evaluate(target_date, insight_snapshot)
        if leakage_result.leakage_detected:
            reason_code = leakage_result.reason_code or ReasonCode.DATA_QUALITY_LEAK_DETECTED
            generation.fail(
                failure_detail=FailureDetail(
                    reason_code=reason_code,
                    detail="RULE-FE-003: feature leakage detected in insight data",
                    retryable=False,
                ),
                processed_at=now,
            )
            return

        # Step 6: Evaluate point-in-time join consistency
        join_result = self._point_in_time_join_policy.evaluate(target_date, insight_snapshot)
        if not join_result.approved:
            generation.fail(
                failure_detail=FailureDetail(
                    reason_code=ReasonCode.DATA_QUALITY_LEAK_DETECTED,
                    detail=f"Point-in-time join rejected: {join_result.reason}",
                    retryable=False,
                ),
                processed_at=now,
            )
            return

        # Step 7: Build and persist feature artifact (RULE-FE-005)
        feature_version = self._feature_generation_factory.generate_feature_version(target_date)
        feature_artifact = FeatureArtifact(
            feature_version=feature_version,
            storage_path=f"{self._storage_path_prefix}/{feature_version}/features.parquet",
            row_count=0,
            feature_count=0,
        )
        self._feature_artifact_repository.persist(feature_artifact)

        # Step 8: Complete generation (RULE-FE-005: complete after storage)
        generation.complete(
            feature_artifact=feature_artifact,
            insight=insight_snapshot,
            processed_at=now,
        )

    def _dispatch_and_finalize(self, generation: FeatureGeneration) -> None:
        """Steps 9-13: Create dispatch, publish event, persist everything, write audit."""
        now = datetime.datetime.now(tz=datetime.UTC)

        # Step 9: Create dispatch aggregate from terminal generation
        dispatch = self._feature_dispatch_factory.from_feature_generation(generation)

        # Step 10-11: Publish integration event and update dispatch state
        try:
            if generation.status == FeatureGenerationStatus.GENERATED:
                completed_event = self._find_or_build_completed_event(generation, now)
                if completed_event is None:
                    dispatch.fail(reason_code=ReasonCode.STATE_CONFLICT, processed_at=now)
                else:
                    self._event_publisher.publish_features_generated(completed_event)
                    dispatch.publish(
                        published_event=PublishedEventType.FEATURES_GENERATED,
                        processed_at=now,
                    )
            elif generation.status == FeatureGenerationStatus.FAILED:
                failed_event = self._find_or_build_failed_event(generation, now)
                if failed_event is None:
                    dispatch.fail(reason_code=ReasonCode.STATE_CONFLICT, processed_at=now)
                else:
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

        self._feature_dispatch_repository.persist(dispatch)

        # Step 12: Persist generation state
        self._feature_generation_repository.persist(generation)

        # Step 13: Persist idempotency key (only on successful non-retryable dispatch)
        # and write audit log.
        # On dispatch failure or retryable generation failure, release the
        # reservation to allow Pub/Sub redelivery.
        retryable_failure = generation.failure_detail is not None and generation.failure_detail.retryable
        if dispatch.dispatch_status == DispatchStatus.PUBLISHED and not retryable_failure:
            self._idempotency_key_repository.persist(
                identifier=generation.identifier,
                processed_at=now,
                trace=generation.trace,
            )
        else:
            self._idempotency_key_repository.terminate(generation.identifier)

        try:
            self._write_audit(generation, dispatch)
        except Exception:
            # Audit failure must not delete an already-persisted idempotency key.
            logger.exception(
                "Failed to write audit log for identifier=%s; idempotency state preserved",
                generation.identifier,
            )

    def _write_audit(self, generation: FeatureGeneration, dispatch: FeatureDispatch) -> None:
        """Write audit log based on generation status and dispatch outcome."""
        if dispatch.dispatch_status == DispatchStatus.FAILED:
            reason_code = dispatch.reason_code or ReasonCode.DISPATCH_FAILED
            self._feature_audit_writer.write_failure(
                identifier=generation.identifier,
                trace=generation.trace,
                reason_code=reason_code,
                detail=f"Dispatch failed: {reason_code.value}",
            )
        elif generation.status == FeatureGenerationStatus.GENERATED:
            feature_artifact = generation.feature_artifact
            if feature_artifact is None:
                logger.error(
                    "Missing feature_artifact for generated feature; identifier=%s, trace=%s",
                    generation.identifier,
                    generation.trace,
                )
                self._feature_audit_writer.write_failure(
                    identifier=generation.identifier,
                    trace=generation.trace,
                    reason_code=ReasonCode.STATE_CONFLICT,
                    detail="Feature artifact missing for GENERATED feature generation.",
                )
            else:
                self._feature_audit_writer.write_success(
                    identifier=generation.identifier,
                    trace=generation.trace,
                    target_date=generation.market.target_date,
                    feature_version=feature_artifact.feature_version,
                )
        elif generation.status == FeatureGenerationStatus.FAILED:
            failure_detail = generation.failure_detail
            if failure_detail is None:
                logger.error(
                    "Missing failure_detail for failed feature generation; identifier=%s, trace=%s",
                    generation.identifier,
                    generation.trace,
                )
                self._feature_audit_writer.write_failure(
                    identifier=generation.identifier,
                    trace=generation.trace,
                    reason_code=ReasonCode.STATE_CONFLICT,
                    detail="Failure detail missing for FAILED feature generation.",
                )
            else:
                self._feature_audit_writer.write_failure(
                    identifier=generation.identifier,
                    trace=generation.trace,
                    reason_code=failure_detail.reason_code,
                    detail=failure_detail.detail,
                )

    def _find_or_build_completed_event(
        self, generation: FeatureGeneration, now: datetime.datetime
    ) -> FeatureGenerationCompleted | None:
        """Extract or rebuild the FeatureGenerationCompleted event.

        Domain events are not restored when aggregates are loaded from the
        repository (dispatch-only retry path). In that case, rebuild the
        event from the persisted generation state.
        """
        for event in generation.domain_events:
            if isinstance(event, FeatureGenerationCompleted):
                return event
        # Rebuild from persisted state (dispatch-only retry)
        if generation.feature_artifact is None:
            return None
        return FeatureGenerationCompleted(
            identifier=generation.identifier,
            target_date=generation.market.target_date,
            feature_version=generation.feature_artifact.feature_version,
            storage_path=generation.feature_artifact.storage_path,
            trace=generation.trace,
            occurred_at=generation.processed_at or now,
        )

    def _find_or_build_failed_event(
        self, generation: FeatureGeneration, now: datetime.datetime
    ) -> FeatureGenerationFailed | None:
        """Extract or rebuild the FeatureGenerationFailed event.

        Domain events are not restored when aggregates are loaded from the
        repository. In that case, rebuild the event from the persisted
        generation state.
        """
        for event in generation.domain_events:
            if isinstance(event, FeatureGenerationFailed):
                return event
        # Rebuild from persisted state
        if generation.failure_detail is None:
            return None
        return FeatureGenerationFailed(
            identifier=generation.identifier,
            reason_code=generation.failure_detail.reason_code,
            detail=generation.failure_detail.detail,
            trace=generation.trace,
            occurred_at=generation.processed_at or now,
        )
