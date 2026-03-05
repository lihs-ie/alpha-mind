"""Tests for FeatureGenerationService usecase.

Covers RULE-FE-001 through RULE-FE-008 via TDD.
"""

import datetime
import unittest.mock
from unittest.mock import MagicMock

import pytest

from domain.event.domain_events import FeatureGenerationCompleted, FeatureGenerationFailed
from domain.factory.feature_dispatch_factory import FeatureDispatchFactory
from domain.factory.feature_generation_factory import FeatureGenerationFactory
from domain.model.feature_dispatch import FeatureDispatch
from domain.model.feature_generation import FeatureGeneration
from domain.repository.feature_artifact_repository import FeatureArtifactRepository
from domain.repository.feature_dispatch_repository import FeatureDispatchRepository
from domain.repository.feature_generation_repository import FeatureGenerationRepository
from domain.repository.idempotency_key_repository import IdempotencyKeyRepository
from domain.repository.insight_record_repository import InsightRecordRepository
from domain.service.feature_leakage_policy import FeatureLeakagePolicy, LeakagePolicyResult
from domain.service.feature_version_generator import FeatureVersionGenerator
from domain.service.point_in_time_join_policy import JoinPolicyResult, PointInTimeJoinPolicy
from domain.value_object.enums import (
    DispatchStatus,
    FeatureGenerationStatus,
    ReasonCode,
    SourceStatusValue,
)
from domain.value_object.failure_detail import FailureDetail
from domain.value_object.feature_artifact import FeatureArtifact
from domain.value_object.insight_snapshot import InsightSnapshot
from domain.value_object.market_snapshot import MarketSnapshot
from domain.value_object.source_status import SourceStatus
from usecase.event_publisher import EventPublisher
from usecase.feature_audit_writer import FeatureAuditWriter
from usecase.feature_generation_service import FeatureGenerationService

VALID_IDENTIFIER = "01JNPQRS000000000000000001"
VALID_TRACE = "01JNPQRS000000000000000002"
TARGET_DATE = datetime.date(2026, 3, 3)
FEATURE_VERSION = "v20260303-001"
STORAGE_PATH = "features/v20260303-001/features.parquet"
MARKET_STORAGE_PATH = "gs://bucket/market/2026-03-03.parquet"


def _make_healthy_market() -> MarketSnapshot:
    return MarketSnapshot(
        target_date=TARGET_DATE,
        storage_path=MARKET_STORAGE_PATH,
        source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
    )


def _make_unhealthy_market() -> MarketSnapshot:
    return MarketSnapshot(
        target_date=TARGET_DATE,
        storage_path=MARKET_STORAGE_PATH,
        source_status=SourceStatus(jp=SourceStatusValue.FAILED, us=SourceStatusValue.OK),
    )


def _make_incomplete_market() -> MarketSnapshot:
    """Market with empty storage_path to trigger RULE-FE-001."""
    return MarketSnapshot(
        target_date=TARGET_DATE,
        storage_path="",
        source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
    )


def _make_insight() -> InsightSnapshot:
    return InsightSnapshot(
        record_count=10,
        latest_collected_at=datetime.datetime(2026, 3, 3, 15, 0, 0, tzinfo=datetime.UTC),
        filtered_by_target_date=True,
    )


def _make_artifact() -> FeatureArtifact:
    return FeatureArtifact(
        feature_version=FEATURE_VERSION,
        storage_path=STORAGE_PATH,
        row_count=500,
        feature_count=120,
    )


class _ServiceFixture:
    """Builds a FeatureGenerationService with all dependencies mocked."""

    def __init__(self) -> None:
        self.feature_generation_repository: MagicMock = MagicMock(spec=FeatureGenerationRepository)
        self.feature_dispatch_repository: MagicMock = MagicMock(spec=FeatureDispatchRepository)
        self.feature_artifact_repository: MagicMock = MagicMock(spec=FeatureArtifactRepository)
        self.idempotency_key_repository: MagicMock = MagicMock(spec=IdempotencyKeyRepository)
        self.insight_record_repository: MagicMock = MagicMock(spec=InsightRecordRepository)

        # Use real factories/policies (they contain domain logic)
        self.feature_version_generator: MagicMock = MagicMock(spec=FeatureVersionGenerator)
        self.feature_version_generator.generate.return_value = FEATURE_VERSION
        self.feature_generation_factory = FeatureGenerationFactory(self.feature_version_generator)
        self.feature_dispatch_factory = FeatureDispatchFactory()

        self.point_in_time_join_policy: PointInTimeJoinPolicy | MagicMock = PointInTimeJoinPolicy()
        self.feature_leakage_policy: FeatureLeakagePolicy | MagicMock = FeatureLeakagePolicy()

        self.event_publisher: MagicMock = MagicMock(spec=EventPublisher)
        self.event_publisher.publish_features_generated.return_value = "msg-001"
        self.event_publisher.publish_features_generation_failed.return_value = "msg-002"

        self.feature_audit_writer: MagicMock = MagicMock(spec=FeatureAuditWriter)

        # Default: no duplicate (reserve succeeds = newly reserved)
        self.idempotency_key_repository.reserve.return_value = True
        # Default: no existing dispatch (step 1b guard)
        self.feature_dispatch_repository.find.return_value = None
        # Default: insight available
        self.insight_record_repository.find_by_target_date.return_value = _make_insight()

    def build(self) -> FeatureGenerationService:
        return FeatureGenerationService(
            feature_generation_repository=self.feature_generation_repository,
            feature_dispatch_repository=self.feature_dispatch_repository,
            feature_artifact_repository=self.feature_artifact_repository,
            idempotency_key_repository=self.idempotency_key_repository,
            insight_record_repository=self.insight_record_repository,
            feature_generation_factory=self.feature_generation_factory,
            feature_dispatch_factory=self.feature_dispatch_factory,
            point_in_time_join_policy=self.point_in_time_join_policy,
            feature_leakage_policy=self.feature_leakage_policy,
            event_publisher=self.event_publisher,
            feature_audit_writer=self.feature_audit_writer,
        )


@pytest.fixture
def fixture() -> _ServiceFixture:
    return _ServiceFixture()


class TestSuccessfulFeatureGeneration:
    """TST-FE-005/006/007: Normal path - artifact persisted, features.generated published."""

    def test_successful_feature_generation(self, fixture: _ServiceFixture) -> None:
        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Artifact should be persisted
        fixture.feature_artifact_repository.persist.assert_called_once()
        persisted_artifact = fixture.feature_artifact_repository.persist.call_args[0][0]
        assert isinstance(persisted_artifact, FeatureArtifact)
        assert persisted_artifact.feature_version == FEATURE_VERSION

        # features.generated event should be published
        fixture.event_publisher.publish_features_generated.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generated.call_args[0][0]
        assert isinstance(published_event, FeatureGenerationCompleted)

        # Dispatch should be persisted
        fixture.feature_dispatch_repository.persist.assert_called_once()

        # Idempotency key should be persisted
        fixture.idempotency_key_repository.persist.assert_called_once()

        # Generation should be persisted
        fixture.feature_generation_repository.persist.assert_called_once()

        # Audit success should be written
        fixture.feature_audit_writer.write_success.assert_called_once()

    def test_generation_persisted_before_idempotency_key(self, fixture: _ServiceFixture) -> None:
        """Generation must be persisted before idempotency key to avoid partial failure state."""
        call_order: list[str] = []

        def track_generation_persist(generation: FeatureGeneration) -> None:
            call_order.append("generation_persist")

        def track_idempotency_persist(identifier: str, processed_at: datetime.datetime, trace: str) -> None:
            call_order.append("idempotency_persist")

        fixture.feature_generation_repository.persist.side_effect = track_generation_persist
        fixture.idempotency_key_repository.persist.side_effect = track_idempotency_persist

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        assert "generation_persist" in call_order
        assert "idempotency_persist" in call_order
        assert call_order.index("generation_persist") < call_order.index("idempotency_persist")


class TestValidationFailedMissingFields:
    """RULE-FE-001: Input validation failure triggers REQUEST_VALIDATION_FAILED."""

    def test_validation_failed_missing_fields(self, fixture: _ServiceFixture) -> None:
        service = fixture.build()
        market = _make_incomplete_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # No artifact should be persisted
        fixture.feature_artifact_repository.persist.assert_not_called()

        # features.generation.failed event should be published
        fixture.event_publisher.publish_features_generation_failed.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generation_failed.call_args[0][0]
        assert isinstance(published_event, FeatureGenerationFailed)
        assert published_event.reason_code == ReasonCode.REQUEST_VALIDATION_FAILED

        # Audit failure should be written
        fixture.feature_audit_writer.write_failure.assert_called_once()
        audit_call = fixture.feature_audit_writer.write_failure.call_args
        assert audit_call[1]["reason_code"] == ReasonCode.REQUEST_VALIDATION_FAILED


class TestSourceStatusUnhealthy:
    """RULE-FE-002: Unhealthy source status triggers DEPENDENCY_UNAVAILABLE."""

    def test_source_status_unhealthy(self, fixture: _ServiceFixture) -> None:
        service = fixture.build()
        market = _make_unhealthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # No artifact should be persisted
        fixture.feature_artifact_repository.persist.assert_not_called()

        # features.generation.failed event should be published
        fixture.event_publisher.publish_features_generation_failed.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generation_failed.call_args[0][0]
        assert isinstance(published_event, FeatureGenerationFailed)
        assert published_event.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE

        # Audit failure should be written
        fixture.feature_audit_writer.write_failure.assert_called_once()
        audit_call = fixture.feature_audit_writer.write_failure.call_args
        assert audit_call[1]["reason_code"] == ReasonCode.DEPENDENCY_UNAVAILABLE


class TestLeakageDetected:
    """RULE-FE-003: Leakage detection triggers DATA_QUALITY_LEAK_DETECTED."""

    def test_leakage_detected(self, fixture: _ServiceFixture) -> None:
        # Insight with future data (latest_collected_at > target_date end-of-day)
        future_insight = InsightSnapshot(
            record_count=5,
            latest_collected_at=datetime.datetime(2026, 3, 4, 1, 0, 0, tzinfo=datetime.UTC),
            filtered_by_target_date=True,
        )
        fixture.insight_record_repository.find_by_target_date.return_value = future_insight

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # No artifact should be persisted
        fixture.feature_artifact_repository.persist.assert_not_called()

        # features.generation.failed event should be published
        fixture.event_publisher.publish_features_generation_failed.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generation_failed.call_args[0][0]
        assert isinstance(published_event, FeatureGenerationFailed)
        assert published_event.reason_code == ReasonCode.DATA_QUALITY_LEAK_DETECTED

        # Audit failure should be written
        fixture.feature_audit_writer.write_failure.assert_called_once()

    def test_leakage_uses_policy_reason_code(self, fixture: _ServiceFixture) -> None:
        """leakage_result.reason_code should be used rather than a hardcoded value."""
        fixture.feature_leakage_policy = MagicMock(spec=FeatureLeakagePolicy)
        fixture.feature_leakage_policy.evaluate.return_value = LeakagePolicyResult(
            leakage_detected=True, reason_code=ReasonCode.DATA_QUALITY_LEAK_DETECTED
        )

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        fixture.event_publisher.publish_features_generation_failed.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generation_failed.call_args[0][0]
        assert published_event.reason_code == ReasonCode.DATA_QUALITY_LEAK_DETECTED


class TestIdempotencyDuplicateEvent:
    """RULE-FE-004: Duplicate identifier causes early return with no side effects."""

    def test_idempotency_duplicate_via_reserve(self, fixture: _ServiceFixture) -> None:
        """reserve() returns False → atomic duplicate detection."""
        fixture.idempotency_key_repository.reserve.return_value = False

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # No side effects
        fixture.feature_artifact_repository.persist.assert_not_called()
        fixture.event_publisher.publish_features_generated.assert_not_called()
        fixture.event_publisher.publish_features_generation_failed.assert_not_called()
        fixture.feature_generation_repository.persist.assert_not_called()
        fixture.feature_dispatch_repository.persist.assert_not_called()

        # Duplicate audit should be written
        fixture.feature_audit_writer.write_duplicate.assert_called_once_with(
            identifier=VALID_IDENTIFIER, trace=VALID_TRACE
        )

    def test_duplicate_via_reserve_skips_dispatch_find(self, fixture: _ServiceFixture) -> None:
        """When reserve() returns False, dispatch repository should not be queried."""
        fixture.idempotency_key_repository.reserve.return_value = False

        service = fixture.build()
        service.execute(identifier=VALID_IDENTIFIER, market=_make_healthy_market(), trace=VALID_TRACE)

        fixture.feature_dispatch_repository.find.assert_not_called()


class TestPublishedDispatchGuardPersistsIdempotencyKey:
    """When PUBLISHED dispatch is detected, idempotency key should be finalized."""

    def test_published_dispatch_persists_idempotency_key(self, fixture: _ServiceFixture) -> None:
        existing_dispatch = MagicMock(spec=FeatureDispatch)
        existing_dispatch.dispatch_status = DispatchStatus.PUBLISHED
        fixture.feature_dispatch_repository.find.return_value = existing_dispatch

        service = fixture.build()
        service.execute(identifier=VALID_IDENTIFIER, market=_make_healthy_market(), trace=VALID_TRACE)

        # Idempotency key must be persisted to prevent reservation leak
        fixture.idempotency_key_repository.persist.assert_called_once()
        persist_call = fixture.idempotency_key_repository.persist.call_args
        assert persist_call[1]["identifier"] == VALID_IDENTIFIER
        assert persist_call[1]["trace"] == VALID_TRACE

        # Duplicate audit should be written
        fixture.feature_audit_writer.write_duplicate.assert_called_once()
        # No processing should occur
        fixture.feature_artifact_repository.persist.assert_not_called()


class TestFeaturesGeneratedAfterStorage:
    """RULE-FE-005: Event is published only after artifact storage succeeds."""

    def test_features_generated_after_storage(self, fixture: _ServiceFixture) -> None:
        call_order: list[str] = []

        def track_artifact_persist(artifact: FeatureArtifact) -> None:
            call_order.append("artifact_persist")

        def track_publish_generated(event: FeatureGenerationCompleted) -> str:
            call_order.append("publish_generated")
            return "msg-001"

        fixture.feature_artifact_repository.persist.side_effect = track_artifact_persist
        fixture.event_publisher.publish_features_generated.side_effect = track_publish_generated

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        assert "artifact_persist" in call_order
        assert "publish_generated" in call_order
        assert call_order.index("artifact_persist") < call_order.index("publish_generated")


class TestArtifactPersistFailureTransitionsToFailed:
    """RULE-FE-005 (negative): If artifact storage fails, generation transitions to FAILED."""

    def test_artifact_persist_failure_transitions_to_failed(self, fixture: _ServiceFixture) -> None:
        fixture.feature_artifact_repository.persist.side_effect = RuntimeError("Storage unavailable")

        service = fixture.build()
        market = _make_healthy_market()

        # Should not raise - exception is caught and generation transitions to FAILED
        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Event must NOT be published as features.generated
        fixture.event_publisher.publish_features_generated.assert_not_called()

        # features.generation.failed should be published
        fixture.event_publisher.publish_features_generation_failed.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generation_failed.call_args[0][0]
        assert isinstance(published_event, FeatureGenerationFailed)
        assert published_event.reason_code == ReasonCode.FEATURE_GENERATION_FAILED

        # Generation should be persisted in FAILED state
        fixture.feature_generation_repository.persist.assert_called_once()

        # Failure audit should be written
        fixture.feature_audit_writer.write_failure.assert_called_once()


class TestFeaturesGeneratedRequiredFields:
    """RULE-FE-007: Published features.generated event has targetDate, featureVersion, storagePath."""

    def test_features_generated_required_fields(self, fixture: _ServiceFixture) -> None:
        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        fixture.event_publisher.publish_features_generated.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generated.call_args[0][0]
        assert isinstance(published_event, FeatureGenerationCompleted)
        # RULE-FE-007: targetDate, featureVersion, storagePath must all be present
        assert published_event.target_date == TARGET_DATE
        assert published_event.feature_version == FEATURE_VERSION
        assert published_event.storage_path  # non-empty storage path required
        assert published_event.identifier == VALID_IDENTIFIER
        assert published_event.trace == VALID_TRACE


class TestFailureWithReasonCode:
    """RULE-FE-008: Failed events carry a reasonCode."""

    def test_failure_with_reason_code(self, fixture: _ServiceFixture) -> None:
        service = fixture.build()
        market = _make_unhealthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        fixture.event_publisher.publish_features_generation_failed.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generation_failed.call_args[0][0]
        assert isinstance(published_event, FeatureGenerationFailed)
        assert published_event.reason_code is not None
        assert isinstance(published_event.reason_code, ReasonCode)


class TestDispatchFailureHandling:
    """Event publish failure should be handled gracefully."""

    def test_dispatch_failure_handling(self, fixture: _ServiceFixture) -> None:
        fixture.event_publisher.publish_features_generated.side_effect = RuntimeError("Pub/Sub unavailable")

        service = fixture.build()
        market = _make_healthy_market()

        # Should not raise - dispatch failure is handled internally
        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Artifact should still be persisted (it happens before publish)
        fixture.feature_artifact_repository.persist.assert_called_once()

        # Dispatch should be persisted with failed status
        fixture.feature_dispatch_repository.persist.assert_called_once()
        persisted_dispatch = fixture.feature_dispatch_repository.persist.call_args[0][0]
        assert isinstance(persisted_dispatch, FeatureDispatch)
        assert persisted_dispatch.dispatch_status == DispatchStatus.FAILED

        # Generation should still be persisted
        fixture.feature_generation_repository.persist.assert_called_once()

        # Idempotency key should NOT be persisted on dispatch failure
        fixture.idempotency_key_repository.persist.assert_not_called()


class TestDispatchFailureWritesFailureAudit:
    """When dispatch fails, audit should record failure, not success."""

    def test_dispatch_failure_writes_failure_audit(self, fixture: _ServiceFixture) -> None:
        fixture.event_publisher.publish_features_generated.side_effect = RuntimeError("Pub/Sub unavailable")

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Should write failure audit, not success audit
        fixture.feature_audit_writer.write_success.assert_not_called()
        fixture.feature_audit_writer.write_failure.assert_called_once()
        audit_call = fixture.feature_audit_writer.write_failure.call_args
        assert audit_call[1]["reason_code"] == ReasonCode.DISPATCH_FAILED


class TestAuditSuccessWritten:
    """Audit log is written on successful feature generation."""

    def test_audit_success_written(self, fixture: _ServiceFixture) -> None:
        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        fixture.feature_audit_writer.write_success.assert_called_once_with(
            identifier=VALID_IDENTIFIER,
            trace=VALID_TRACE,
            target_date=TARGET_DATE,
            feature_version=FEATURE_VERSION,
        )


class TestAuditFailureWritten:
    """Audit log is written on failed feature generation."""

    def test_audit_failure_written(self, fixture: _ServiceFixture) -> None:
        service = fixture.build()
        market = _make_unhealthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        fixture.feature_audit_writer.write_failure.assert_called_once()
        audit_call = fixture.feature_audit_writer.write_failure.call_args
        assert audit_call[1]["identifier"] == VALID_IDENTIFIER
        assert audit_call[1]["trace"] == VALID_TRACE
        assert audit_call[1]["reason_code"] == ReasonCode.DEPENDENCY_UNAVAILABLE


class TestAuditDuplicateWritten:
    """Audit log is written on duplicate event detection."""

    def test_audit_duplicate_written(self, fixture: _ServiceFixture) -> None:
        fixture.idempotency_key_repository.reserve.return_value = False

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        fixture.feature_audit_writer.write_duplicate.assert_called_once_with(
            identifier=VALID_IDENTIFIER,
            trace=VALID_TRACE,
        )


class TestInsightSnapshotNone:
    """When insight_record_repository returns None, an empty InsightSnapshot is used."""

    def test_proceeds_with_empty_insight_when_none(self, fixture: _ServiceFixture) -> None:
        fixture.insight_record_repository.find_by_target_date.return_value = None

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Should still succeed since empty insight (record_count=0, latest_collected_at=None)
        # does not trigger leakage detection
        fixture.feature_artifact_repository.persist.assert_called_once()
        fixture.event_publisher.publish_features_generated.assert_called_once()
        fixture.feature_audit_writer.write_success.assert_called_once()


class TestCompletedEventRebuiltWhenDomainEventsCleared:
    """When domain_events are cleared, the event is rebuilt from generation state."""

    def test_event_rebuilt_from_state_when_domain_events_cleared(self, fixture: _ServiceFixture) -> None:
        original_complete = FeatureGeneration.complete

        def complete_and_clear_events(
            self: FeatureGeneration,
            feature_artifact: FeatureArtifact,
            insight: InsightSnapshot,
            processed_at: datetime.datetime,
        ) -> ReasonCode | None:
            result = original_complete(self, feature_artifact, insight, processed_at)
            self.clear_domain_events()
            return result

        with unittest.mock.patch.object(FeatureGeneration, "complete", complete_and_clear_events):
            service = fixture.build()
            market = _make_healthy_market()

            service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Event is rebuilt from generation state → publish succeeds
        fixture.event_publisher.publish_features_generated.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generated.call_args[0][0]
        assert isinstance(published_event, FeatureGenerationCompleted)
        assert published_event.feature_version == FEATURE_VERSION
        # Dispatch should be PUBLISHED
        fixture.feature_dispatch_repository.persist.assert_called_once()
        persisted_dispatch = fixture.feature_dispatch_repository.persist.call_args[0][0]
        assert persisted_dispatch.dispatch_status == DispatchStatus.PUBLISHED


class TestFailedEventRebuiltWhenDomainEventsCleared:
    """When domain_events are cleared before dispatch, the failed event is rebuilt from state."""

    def test_failed_event_rebuilt_from_state(self, fixture: _ServiceFixture) -> None:
        original_fail = FeatureGeneration.fail

        def fail_and_clear_events(
            self: FeatureGeneration,
            failure_detail: FailureDetail,
            processed_at: datetime.datetime,
        ) -> None:
            original_fail(self, failure_detail, processed_at)
            self.clear_domain_events()

        with unittest.mock.patch.object(FeatureGeneration, "fail", fail_and_clear_events):
            service = fixture.build()
            market = _make_unhealthy_market()

            service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Event is rebuilt from failure_detail → publish succeeds
        fixture.event_publisher.publish_features_generation_failed.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generation_failed.call_args[0][0]
        assert isinstance(published_event, FeatureGenerationFailed)
        assert published_event.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE
        # Dispatch should be PUBLISHED (not FAILED/STATE_CONFLICT)
        fixture.feature_dispatch_repository.persist.assert_called_once()
        persisted_dispatch = fixture.feature_dispatch_repository.persist.call_args[0][0]
        assert persisted_dispatch.dispatch_status == DispatchStatus.PUBLISHED


class TestPointInTimeJoinPolicyRejection:
    """Step 6: PointInTimeJoinPolicy rejection fails the generation."""

    def test_join_policy_rejection_fails_generation(self, fixture: _ServiceFixture) -> None:
        # Mock leakage policy to pass, but mock join policy to reject
        fixture.feature_leakage_policy = MagicMock(spec=FeatureLeakagePolicy)
        fixture.feature_leakage_policy.evaluate.return_value = LeakagePolicyResult(
            leakage_detected=False, reason_code=None
        )
        fixture.point_in_time_join_policy = MagicMock(spec=PointInTimeJoinPolicy)
        fixture.point_in_time_join_policy.evaluate.return_value = JoinPolicyResult(
            approved=False, reason="Insight snapshot was not filtered by target_date"
        )

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # No artifact should be persisted
        fixture.feature_artifact_repository.persist.assert_not_called()

        # features.generation.failed event should be published
        fixture.event_publisher.publish_features_generation_failed.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generation_failed.call_args[0][0]
        assert isinstance(published_event, FeatureGenerationFailed)
        assert published_event.reason_code == ReasonCode.DATA_QUALITY_LEAK_DETECTED

        # Audit failure should be written
        fixture.feature_audit_writer.write_failure.assert_called_once()


class TestStoragePathUsesConfiguredPrefix:
    """Storage path should use the configured prefix, not hardcoded infrastructure details."""

    def test_storage_path_uses_configured_prefix(self, fixture: _ServiceFixture) -> None:
        service = FeatureGenerationService(
            feature_generation_repository=fixture.feature_generation_repository,
            feature_dispatch_repository=fixture.feature_dispatch_repository,
            feature_artifact_repository=fixture.feature_artifact_repository,
            idempotency_key_repository=fixture.idempotency_key_repository,
            insight_record_repository=fixture.insight_record_repository,
            feature_generation_factory=fixture.feature_generation_factory,
            feature_dispatch_factory=fixture.feature_dispatch_factory,
            point_in_time_join_policy=fixture.point_in_time_join_policy,
            feature_leakage_policy=fixture.feature_leakage_policy,
            event_publisher=fixture.event_publisher,
            feature_audit_writer=fixture.feature_audit_writer,
            storage_path_prefix="gs://my-bucket/features",
        )
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        persisted_artifact = fixture.feature_artifact_repository.persist.call_args[0][0]
        assert persisted_artifact.storage_path.startswith("gs://my-bucket/features/")

    def test_storage_path_prefix_trailing_slash_normalized(self, fixture: _ServiceFixture) -> None:
        """Trailing slash in prefix should not produce double slashes."""
        service = FeatureGenerationService(
            feature_generation_repository=fixture.feature_generation_repository,
            feature_dispatch_repository=fixture.feature_dispatch_repository,
            feature_artifact_repository=fixture.feature_artifact_repository,
            idempotency_key_repository=fixture.idempotency_key_repository,
            insight_record_repository=fixture.insight_record_repository,
            feature_generation_factory=fixture.feature_generation_factory,
            feature_dispatch_factory=fixture.feature_dispatch_factory,
            point_in_time_join_policy=fixture.point_in_time_join_policy,
            feature_leakage_policy=fixture.feature_leakage_policy,
            event_publisher=fixture.event_publisher,
            feature_audit_writer=fixture.feature_audit_writer,
            storage_path_prefix="gs://my-bucket/features/",
        )
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        persisted_artifact = fixture.feature_artifact_repository.persist.call_args[0][0]
        assert "//" not in persisted_artifact.storage_path.replace("gs://", "", 1)


class TestProcessingExceptionTransitionsToFailed:
    """Unexpected exceptions during steps 4-8 should transition generation to FAILED."""

    def test_insight_fetch_exception_transitions_to_failed(self, fixture: _ServiceFixture) -> None:
        fixture.insight_record_repository.find_by_target_date.side_effect = ConnectionError("Firestore unavailable")

        service = fixture.build()
        market = _make_healthy_market()

        # Should not raise - exception is caught, generation transitions to FAILED
        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # features.generation.failed should be published
        fixture.event_publisher.publish_features_generation_failed.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generation_failed.call_args[0][0]
        assert isinstance(published_event, FeatureGenerationFailed)
        assert published_event.reason_code == ReasonCode.FEATURE_GENERATION_FAILED

        # Generation and dispatch should be persisted
        fixture.feature_generation_repository.persist.assert_called_once()
        fixture.feature_dispatch_repository.persist.assert_called_once()

        # Failure audit should be written
        fixture.feature_audit_writer.write_failure.assert_called_once()


class TestAuditWithMissingFeatureArtifact:
    """When feature_artifact is None for GENERATED status, audit writes failure with STATE_CONFLICT."""

    def test_missing_feature_artifact_writes_failure_audit(self, fixture: _ServiceFixture) -> None:
        original_complete = FeatureGeneration.complete

        def complete_and_clear_artifact(
            self: FeatureGeneration,
            feature_artifact: FeatureArtifact,
            insight: InsightSnapshot,
            processed_at: datetime.datetime,
        ) -> ReasonCode | None:
            result = original_complete(self, feature_artifact, insight, processed_at)
            # Forcibly clear artifact to simulate inconsistent state
            self._feature_artifact = None
            return result

        with unittest.mock.patch.object(FeatureGeneration, "complete", complete_and_clear_artifact):
            service = fixture.build()
            market = _make_healthy_market()

            service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Should write failure audit with STATE_CONFLICT, not success
        fixture.feature_audit_writer.write_success.assert_not_called()
        fixture.feature_audit_writer.write_failure.assert_called_once()
        audit_call = fixture.feature_audit_writer.write_failure.call_args
        assert audit_call[1]["reason_code"] == ReasonCode.STATE_CONFLICT


class TestDispatchExistsGuard:
    """Step 1b: PUBLISHED dispatch prevents re-processing; FAILED dispatch allows retry."""

    def test_published_dispatch_skips_processing(self, fixture: _ServiceFixture) -> None:
        """If a PUBLISHED dispatch exists, skip re-processing (duplicate)."""
        existing_dispatch = MagicMock(spec=FeatureDispatch)
        existing_dispatch.dispatch_status = DispatchStatus.PUBLISHED
        fixture.feature_dispatch_repository.find.return_value = existing_dispatch

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # No processing should occur
        fixture.feature_artifact_repository.persist.assert_not_called()
        fixture.event_publisher.publish_features_generated.assert_not_called()
        fixture.event_publisher.publish_features_generation_failed.assert_not_called()
        fixture.feature_generation_repository.persist.assert_not_called()

        # Duplicate audit should be written
        fixture.feature_audit_writer.write_duplicate.assert_called_once_with(
            identifier=VALID_IDENTIFIER, trace=VALID_TRACE
        )

    def test_failed_dispatch_allows_retry(self, fixture: _ServiceFixture) -> None:
        """If a FAILED dispatch exists, re-processing is allowed (not duplicate)."""
        existing_dispatch = MagicMock(spec=FeatureDispatch)
        existing_dispatch.dispatch_status = DispatchStatus.FAILED
        fixture.feature_dispatch_repository.find.return_value = existing_dispatch

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Processing should proceed normally
        fixture.feature_artifact_repository.persist.assert_called_once()
        fixture.event_publisher.publish_features_generated.assert_called_once()
        fixture.feature_audit_writer.write_duplicate.assert_not_called()

    def test_no_existing_dispatch_proceeds_normally(self, fixture: _ServiceFixture) -> None:
        """When no dispatch exists, processing proceeds normally."""
        fixture.feature_dispatch_repository.find.return_value = None

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Normal processing should occur
        fixture.feature_artifact_repository.persist.assert_called_once()
        fixture.event_publisher.publish_features_generated.assert_called_once()


class TestReservationReleaseOnDispatchFailure:
    """When dispatch fails, the idempotency reservation is released to allow retry."""

    def test_dispatch_failure_releases_reservation(self, fixture: _ServiceFixture) -> None:
        fixture.event_publisher.publish_features_generated.side_effect = RuntimeError("Pub/Sub unavailable")

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Reservation should be released (terminate called)
        fixture.idempotency_key_repository.terminate.assert_called_once_with(VALID_IDENTIFIER)
        # Idempotency key should NOT be persisted (dispatch failed)
        fixture.idempotency_key_repository.persist.assert_not_called()

    def test_successful_dispatch_persists_idempotency_key(self, fixture: _ServiceFixture) -> None:
        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Idempotency key should be persisted (dispatch succeeded)
        fixture.idempotency_key_repository.persist.assert_called_once()
        # Reservation should NOT be released
        fixture.idempotency_key_repository.terminate.assert_not_called()


class TestRecoverableVsUnrecoverableProcessingError:
    """Processing errors are classified as recoverable or non-recoverable."""

    def test_connection_error_is_retryable(self, fixture: _ServiceFixture) -> None:
        fixture.insight_record_repository.find_by_target_date.side_effect = ConnectionError("Firestore unavailable")

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Should be published as failed with retryable=True
        fixture.event_publisher.publish_features_generation_failed.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generation_failed.call_args[0][0]
        assert isinstance(published_event, FeatureGenerationFailed)
        assert published_event.reason_code == ReasonCode.FEATURE_GENERATION_FAILED

        # Generation should have retryable failure detail
        persisted_generation = fixture.feature_generation_repository.persist.call_args[0][0]
        assert persisted_generation.failure_detail is not None
        assert persisted_generation.failure_detail.retryable is True

    def test_unexpected_error_is_retryable(self, fixture: _ServiceFixture) -> None:
        """Unexpected errors (including Google API exceptions) are treated as retryable
        since the usecase layer cannot distinguish transient infrastructure failures
        from programming errors without importing infrastructure-specific exceptions.
        """
        fixture.insight_record_repository.find_by_target_date.side_effect = ValueError("Unexpected bug")

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Should be published as failed with retryable=True
        fixture.event_publisher.publish_features_generation_failed.assert_called_once()

        # Generation should have retryable failure detail
        persisted_generation = fixture.feature_generation_repository.persist.call_args[0][0]
        assert persisted_generation.failure_detail is not None
        assert persisted_generation.failure_detail.retryable is True


class TestDispatchPublishCatchesAllExceptions:
    """All publisher exceptions are caught to ensure dispatch/generation state is persisted."""

    def test_unexpected_exception_type_caught(self, fixture: _ServiceFixture) -> None:
        """Even unexpected exception types (e.g., ValueError) are caught during publish."""
        fixture.event_publisher.publish_features_generated.side_effect = ValueError("Unexpected serialization error")

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Dispatch should be persisted with FAILED status
        fixture.feature_dispatch_repository.persist.assert_called_once()
        persisted_dispatch = fixture.feature_dispatch_repository.persist.call_args[0][0]
        assert persisted_dispatch.dispatch_status == DispatchStatus.FAILED

        # Generation should still be persisted
        fixture.feature_generation_repository.persist.assert_called_once()

        # Idempotency key should NOT be persisted
        fixture.idempotency_key_repository.persist.assert_not_called()


class TestAuditWithMissingFailureDetail:
    """When failure_detail is None for FAILED status, audit writes failure with STATE_CONFLICT."""

    def test_missing_failure_detail_writes_failure_audit(self, fixture: _ServiceFixture) -> None:
        original_fail = FeatureGeneration.fail

        def fail_and_clear_detail(
            self: FeatureGeneration,
            failure_detail: FailureDetail,
            processed_at: datetime.datetime,
        ) -> None:
            original_fail(self, failure_detail, processed_at)
            # Forcibly clear failure_detail to simulate inconsistent state
            self._failure_detail = None

        with unittest.mock.patch.object(FeatureGeneration, "fail", fail_and_clear_detail):
            service = fixture.build()
            market = _make_unhealthy_market()

            service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Should write failure audit with STATE_CONFLICT
        fixture.feature_audit_writer.write_failure.assert_called()
        # Find the audit call that has STATE_CONFLICT (dispatch audit might also be called)
        found_state_conflict = False
        for call in fixture.feature_audit_writer.write_failure.call_args_list:
            if call[1].get("reason_code") == ReasonCode.STATE_CONFLICT:
                found_state_conflict = True
                break
        assert found_state_conflict, "Expected STATE_CONFLICT audit for missing failure_detail"


class TestFeatureVersionImmutability:
    """TST-FE-006 / RULE-FE-006: featureVersion is generated once and never re-generated."""

    def test_feature_version_generated_once_per_execution(self, fixture: _ServiceFixture) -> None:
        """generate_feature_version is called exactly once during successful processing."""
        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        fixture.feature_version_generator.generate.assert_called_once_with(TARGET_DATE)

        # The persisted artifact must carry the version from the generator
        persisted_artifact = fixture.feature_artifact_repository.persist.call_args[0][0]
        assert persisted_artifact.feature_version == FEATURE_VERSION

    def test_feature_version_not_regenerated_on_failed_dispatch_retry(self, fixture: _ServiceFixture) -> None:
        """INV-FE-005: When retrying after a FAILED dispatch, featureVersion must not change.

        The generator is called once per execute() invocation; its deterministic
        output for the same target_date ensures immutability across retries.
        """
        # Simulate FAILED dispatch existing (allows retry)
        existing_dispatch = MagicMock(spec=FeatureDispatch)
        existing_dispatch.dispatch_status = DispatchStatus.FAILED
        fixture.feature_dispatch_repository.find.return_value = existing_dispatch

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # generate is still called exactly once per execute invocation
        fixture.feature_version_generator.generate.assert_called_once_with(TARGET_DATE)

        # The version must match the generator's output
        persisted_artifact = fixture.feature_artifact_repository.persist.call_args[0][0]
        assert persisted_artifact.feature_version == FEATURE_VERSION


class TestIdentifierNamingConvention:
    """TST-FE-009 / RULE-FE-009: Domain model uses 'identifier' not 'id' or 'Id'."""

    def test_domain_events_use_identifier_field(self, fixture: _ServiceFixture) -> None:
        """FeatureGenerationCompleted and FeatureGenerationFailed use 'identifier'."""
        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        completed_event = fixture.event_publisher.publish_features_generated.call_args[0][0]
        assert hasattr(completed_event, "identifier")
        assert not hasattr(completed_event, "id")
        assert completed_event.identifier == VALID_IDENTIFIER

    def test_failed_event_uses_identifier_field(self, fixture: _ServiceFixture) -> None:
        """FeatureGenerationFailed uses 'identifier' not 'id'."""
        service = fixture.build()
        market = _make_unhealthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        failed_event = fixture.event_publisher.publish_features_generation_failed.call_args[0][0]
        assert hasattr(failed_event, "identifier")
        assert not hasattr(failed_event, "id")
        assert failed_event.identifier == VALID_IDENTIFIER

    def test_generation_aggregate_uses_identifier_field(self, fixture: _ServiceFixture) -> None:
        """FeatureGeneration aggregate uses 'identifier' not 'id'."""
        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        persisted_generation = fixture.feature_generation_repository.persist.call_args[0][0]
        assert hasattr(persisted_generation, "identifier")
        assert not hasattr(persisted_generation, "id")
        assert persisted_generation.identifier == VALID_IDENTIFIER


class TestReservationReleasedOnPreProcessingError:
    """#16: reserve() success followed by exception before _dispatch_and_finalize must release reservation."""

    def test_dispatch_find_raises_releases_reservation(self, fixture: _ServiceFixture) -> None:
        """If feature_dispatch_repository.find() throws after reserve(), reservation is released."""
        fixture.feature_dispatch_repository.find.side_effect = ConnectionError("Firestore unavailable")

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Reservation must be released so retries are not blocked
        fixture.idempotency_key_repository.terminate.assert_called_once_with(VALID_IDENTIFIER)
        fixture.idempotency_key_repository.persist.assert_not_called()

    def test_factory_raises_releases_reservation(self, fixture: _ServiceFixture) -> None:
        """If feature_generation_factory.from_market_collected_event() throws, reservation is released."""
        fixture.feature_generation_factory = MagicMock(spec=FeatureGenerationFactory)
        fixture.feature_generation_factory.from_market_collected_event.side_effect = RuntimeError("Factory boom")

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        fixture.idempotency_key_repository.terminate.assert_called_once_with(VALID_IDENTIFIER)
        fixture.idempotency_key_repository.persist.assert_not_called()


class TestReservationReleasedOnFinalizationPersistError:
    """#14: If persist in _dispatch_and_finalize raises, reservation must still be finalized."""

    def test_generation_persist_raises_releases_reservation(self, fixture: _ServiceFixture) -> None:
        """If feature_generation_repository.persist() throws, reservation is released."""
        fixture.feature_generation_repository.persist.side_effect = ConnectionError("Firestore unavailable")

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Reservation must be released despite persist failure
        fixture.idempotency_key_repository.terminate.assert_called_once_with(VALID_IDENTIFIER)

    def test_dispatch_persist_raises_releases_reservation(self, fixture: _ServiceFixture) -> None:
        """If feature_dispatch_repository.persist() throws, reservation is released."""
        fixture.feature_dispatch_repository.persist.side_effect = ConnectionError("Firestore unavailable")

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        fixture.idempotency_key_repository.terminate.assert_called_once_with(VALID_IDENTIFIER)


class TestDispatchOnlyRetryReusesExistingGeneration:
    """#19: When retrying after dispatch-only failure, reuse persisted GENERATED generation."""

    def test_failed_dispatch_with_generated_generation_reuses_state(self, fixture: _ServiceFixture) -> None:
        """If FAILED dispatch + GENERATED generation exist, skip re-processing and dispatch only."""
        existing_dispatch = MagicMock(spec=FeatureDispatch)
        existing_dispatch.dispatch_status = DispatchStatus.FAILED
        fixture.feature_dispatch_repository.find.return_value = existing_dispatch

        # Simulate a previously persisted GENERATED generation (no domain events —
        # domain events are not restored by the repository deserializer).
        artifact = _make_artifact()
        existing_generation = FeatureGeneration(
            identifier=VALID_IDENTIFIER,
            status=FeatureGenerationStatus.GENERATED,
            market=_make_healthy_market(),
            trace=VALID_TRACE,
            feature_artifact=artifact,
            insight=_make_insight(),
            processed_at=datetime.datetime(2026, 3, 3, 16, 0, 0, tzinfo=datetime.UTC),
        )
        fixture.feature_generation_repository.find.return_value = existing_generation

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Should NOT re-process features (no artifact persist, no factory feature_version call)
        fixture.feature_artifact_repository.persist.assert_not_called()

        # Should publish features.generated using the existing generation
        fixture.event_publisher.publish_features_generated.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generated.call_args[0][0]
        assert published_event.feature_version == FEATURE_VERSION

        # Idempotency key should be persisted on success
        fixture.idempotency_key_repository.persist.assert_called_once()

    def test_failed_dispatch_without_existing_generation_processes_normally(self, fixture: _ServiceFixture) -> None:
        """If FAILED dispatch exists but no persisted generation, process from scratch."""
        existing_dispatch = MagicMock(spec=FeatureDispatch)
        existing_dispatch.dispatch_status = DispatchStatus.FAILED
        fixture.feature_dispatch_repository.find.return_value = existing_dispatch
        fixture.feature_generation_repository.find.return_value = None

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Should process normally
        fixture.feature_artifact_repository.persist.assert_called_once()
        fixture.event_publisher.publish_features_generated.assert_called_once()


class TestAuditWriteFailurePreservesIdempotencyKey:
    """#22: audit write failure must not delete an already-persisted idempotency key."""

    def test_audit_failure_does_not_terminate_persisted_key(self, fixture: _ServiceFixture) -> None:
        """If _write_audit raises after successful dispatch, idempotency key remains persisted."""
        fixture.feature_audit_writer.write_success.side_effect = RuntimeError("Logging service unavailable")

        service = fixture.build()
        market = _make_healthy_market()

        service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Idempotency key should be persisted (dispatch succeeded)
        fixture.idempotency_key_repository.persist.assert_called_once()
        # terminate must NOT be called — the key was already finalized
        fixture.idempotency_key_repository.terminate.assert_not_called()


class TestDispatchOnlyRetryRebuildsEventFromState:
    """#20: Persisted aggregates have no domain events; event must be rebuilt from state."""

    def test_rebuilt_completed_event_matches_persisted_state(self, fixture: _ServiceFixture) -> None:
        """Event rebuilt from generation state has correct field values."""
        existing_dispatch = MagicMock(spec=FeatureDispatch)
        existing_dispatch.dispatch_status = DispatchStatus.FAILED
        fixture.feature_dispatch_repository.find.return_value = existing_dispatch

        artifact = _make_artifact()
        existing_generation = FeatureGeneration(
            identifier=VALID_IDENTIFIER,
            status=FeatureGenerationStatus.GENERATED,
            market=_make_healthy_market(),
            trace=VALID_TRACE,
            feature_artifact=artifact,
            insight=_make_insight(),
            processed_at=datetime.datetime(2026, 3, 3, 16, 0, 0, tzinfo=datetime.UTC),
        )
        # No domain events — simulates repository deserialization
        fixture.feature_generation_repository.find.return_value = existing_generation

        service = fixture.build()
        service.execute(identifier=VALID_IDENTIFIER, market=_make_healthy_market(), trace=VALID_TRACE)

        fixture.event_publisher.publish_features_generated.assert_called_once()
        published_event = fixture.event_publisher.publish_features_generated.call_args[0][0]
        assert published_event.identifier == VALID_IDENTIFIER
        assert published_event.target_date == TARGET_DATE
        assert published_event.feature_version == FEATURE_VERSION
        assert published_event.storage_path == STORAGE_PATH
        assert published_event.trace == VALID_TRACE
