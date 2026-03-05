"""Tests for FeatureGenerationService usecase.

Covers RULE-FE-001 through RULE-FE-008 via TDD.
"""

import datetime
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
from domain.service.feature_leakage_policy import FeatureLeakagePolicy
from domain.service.feature_version_generator import FeatureVersionGenerator
from domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
from domain.value_object.enums import (
    DispatchStatus,
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

        self.point_in_time_join_policy = PointInTimeJoinPolicy()
        self.feature_leakage_policy = FeatureLeakagePolicy()

        self.event_publisher: MagicMock = MagicMock(spec=EventPublisher)
        self.event_publisher.publish_features_generated.return_value = "msg-001"
        self.event_publisher.publish_features_generation_failed.return_value = "msg-002"

        self.feature_audit_writer: MagicMock = MagicMock(spec=FeatureAuditWriter)

        # Default: no duplicate
        self.idempotency_key_repository.find.return_value = None
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


class TestIdempotencyDuplicateEvent:
    """RULE-FE-004: Duplicate identifier causes early return with no side effects."""

    def test_idempotency_duplicate_event(self, fixture: _ServiceFixture) -> None:
        fixture.idempotency_key_repository.find.return_value = datetime.datetime(
            2026, 3, 3, 10, 0, 0, tzinfo=datetime.UTC
        )

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


class TestArtifactPersistFailurePreventsPublish:
    """RULE-FE-005 (negative): If artifact storage fails, event must NOT be published."""

    def test_artifact_persist_failure_prevents_publish(self, fixture: _ServiceFixture) -> None:
        fixture.feature_artifact_repository.persist.side_effect = RuntimeError("Storage unavailable")

        service = fixture.build()
        market = _make_healthy_market()

        with pytest.raises(RuntimeError, match="Storage unavailable"):
            service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # Event must NOT be published since artifact storage failed
        fixture.event_publisher.publish_features_generated.assert_not_called()
        fixture.event_publisher.publish_features_generation_failed.assert_not_called()


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
        fixture.idempotency_key_repository.find.return_value = datetime.datetime(
            2026, 3, 3, 10, 0, 0, tzinfo=datetime.UTC
        )

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


class TestCompletedEventNotFoundInDomainEvents:
    """When domain_events are cleared before dispatch, dispatch fails with STATE_CONFLICT."""

    def test_dispatch_fails_when_completed_event_missing(self, fixture: _ServiceFixture) -> None:
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

        import unittest.mock

        with unittest.mock.patch.object(FeatureGeneration, "complete", complete_and_clear_events):
            service = fixture.build()
            market = _make_healthy_market()

            service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # publish_features_generated should NOT be called since event was not found
        fixture.event_publisher.publish_features_generated.assert_not_called()
        # Dispatch should be persisted with FAILED / STATE_CONFLICT
        fixture.feature_dispatch_repository.persist.assert_called_once()
        persisted_dispatch = fixture.feature_dispatch_repository.persist.call_args[0][0]
        assert persisted_dispatch.dispatch_status == DispatchStatus.FAILED
        assert persisted_dispatch.reason_code == ReasonCode.STATE_CONFLICT
        # Idempotency key should NOT be persisted
        fixture.idempotency_key_repository.persist.assert_not_called()
        # Generation should still be persisted
        fixture.feature_generation_repository.persist.assert_called_once()
        # Failure audit should be written
        fixture.feature_audit_writer.write_failure.assert_called_once()


class TestFailedEventNotFoundInDomainEvents:
    """When domain_events are cleared before dispatch, failed dispatch uses STATE_CONFLICT."""

    def test_dispatch_fails_when_failed_event_missing(self, fixture: _ServiceFixture) -> None:
        original_fail = FeatureGeneration.fail

        def fail_and_clear_events(
            self: FeatureGeneration,
            failure_detail: FailureDetail,
            processed_at: datetime.datetime,
        ) -> None:
            original_fail(self, failure_detail, processed_at)
            self.clear_domain_events()

        import unittest.mock

        with unittest.mock.patch.object(FeatureGeneration, "fail", fail_and_clear_events):
            service = fixture.build()
            market = _make_unhealthy_market()

            service.execute(identifier=VALID_IDENTIFIER, market=market, trace=VALID_TRACE)

        # publish_features_generation_failed should NOT be called since event was not found
        fixture.event_publisher.publish_features_generation_failed.assert_not_called()
        # Dispatch should be FAILED / STATE_CONFLICT
        fixture.feature_dispatch_repository.persist.assert_called_once()
        persisted_dispatch = fixture.feature_dispatch_repository.persist.call_args[0][0]
        assert persisted_dispatch.dispatch_status == DispatchStatus.FAILED
        assert persisted_dispatch.reason_code == ReasonCode.STATE_CONFLICT
        # Idempotency key should NOT be persisted
        fixture.idempotency_key_repository.persist.assert_not_called()
        # Generation should still be persisted
        fixture.feature_generation_repository.persist.assert_called_once()


class TestPointInTimeJoinPolicyRejection:
    """Step 6: PointInTimeJoinPolicy rejection fails the generation."""

    def test_join_policy_rejection_fails_generation(self, fixture: _ServiceFixture) -> None:
        from domain.service.feature_leakage_policy import LeakagePolicyResult
        from domain.service.point_in_time_join_policy import JoinPolicyResult

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
