"""Tests for FeatureGeneration aggregate root."""

import datetime

import pytest
from src.domain.event.domain_events import FeatureGenerationCompleted, FeatureGenerationFailed
from src.domain.model.feature_generation import FeatureGeneration, InvalidStateTransitionError
from src.domain.value_object.enums import (
    FeatureGenerationStatus,
    ReasonCode,
    SourceStatusValue,
)
from src.domain.value_object.failure_detail import FailureDetail
from src.domain.value_object.feature_artifact import FeatureArtifact
from src.domain.value_object.insight_snapshot import InsightSnapshot
from src.domain.value_object.market_snapshot import MarketSnapshot
from src.domain.value_object.source_status import SourceStatus


def _make_pending_generation() -> FeatureGeneration:
    """Helper to create a pending FeatureGeneration for testing."""
    return FeatureGeneration(
        identifier="01JNPQRS0000000000000001",
        status=FeatureGenerationStatus.PENDING,
        market=MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="gs://bucket/market/2026-03-03.parquet",
            source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
        ),
        trace="trace-abc-123",
    )


def _make_artifact() -> FeatureArtifact:
    return FeatureArtifact(
        feature_version="v20260303-001",
        storage_path="gs://bucket/features/v20260303-001.parquet",
        row_count=500,
        feature_count=120,
    )


def _make_insight() -> InsightSnapshot:
    return InsightSnapshot(
        record_count=10,
        latest_collected_at=datetime.datetime(2026, 3, 3, 15, 0, 0, tzinfo=datetime.UTC),
        filtered_by_target_date=True,
    )


class TestFeatureGenerationCreation:
    def test_initial_state_is_pending(self) -> None:
        generation = _make_pending_generation()
        assert generation.status == FeatureGenerationStatus.PENDING

    def test_identifier_is_set(self) -> None:
        generation = _make_pending_generation()
        assert generation.identifier == "01JNPQRS0000000000000001"

    def test_no_domain_events_on_direct_construction(self) -> None:
        generation = _make_pending_generation()
        assert generation.domain_events == []

    def test_rejects_empty_identifier(self) -> None:
        with pytest.raises(ValueError, match="identifier must not be empty"):
            FeatureGeneration(
                identifier="",
                status=FeatureGenerationStatus.PENDING,
                market=MarketSnapshot(
                    target_date=datetime.date(2026, 3, 3),
                    storage_path="gs://bucket/path",
                    source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
                ),
                trace="trace-abc-123",
            )

    def test_rejects_empty_trace(self) -> None:
        with pytest.raises(ValueError, match="trace must not be empty"):
            FeatureGeneration(
                identifier="01JNPQRS0000000000000001",
                status=FeatureGenerationStatus.PENDING,
                market=MarketSnapshot(
                    target_date=datetime.date(2026, 3, 3),
                    storage_path="gs://bucket/path",
                    source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
                ),
                trace="",
            )

    def test_inv_fe_001_rejects_generated_without_artifact(self) -> None:
        """INV-FE-001: generated status requires feature_artifact at construction."""
        with pytest.raises(ValueError, match="INV-FE-001"):
            FeatureGeneration(
                identifier="01JNPQRS0000000000000001",
                status=FeatureGenerationStatus.GENERATED,
                market=MarketSnapshot(
                    target_date=datetime.date(2026, 3, 3),
                    storage_path="gs://bucket/path",
                    source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
                ),
                trace="trace-abc-123",
                feature_artifact=None,
            )

    def test_inv_fe_002_rejects_failed_without_failure_detail(self) -> None:
        """INV-FE-002: failed status requires failure_detail at construction."""
        with pytest.raises(ValueError, match="INV-FE-002"):
            FeatureGeneration(
                identifier="01JNPQRS0000000000000001",
                status=FeatureGenerationStatus.FAILED,
                market=MarketSnapshot(
                    target_date=datetime.date(2026, 3, 3),
                    storage_path="gs://bucket/path",
                    source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
                ),
                trace="trace-abc-123",
                failure_detail=None,
            )


class TestFeatureGenerationCompleteTransition:
    def test_transition_to_generated(self) -> None:
        generation = _make_pending_generation()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)

        generation.complete(
            feature_artifact=_make_artifact(),
            insight=_make_insight(),
            processed_at=processed_at,
        )

        assert generation.status == FeatureGenerationStatus.GENERATED
        assert generation.feature_artifact is not None
        assert generation.feature_artifact.feature_version == "v20260303-001"
        assert generation.insight is not None
        assert generation.processed_at == processed_at

    def test_inv_fe_001_generated_state_has_required_fields(self) -> None:
        """INV-FE-001: generated state requires feature_version, storage_path, row_count, feature_count."""
        generation = _make_pending_generation()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        artifact = _make_artifact()

        generation.complete(feature_artifact=artifact, insight=_make_insight(), processed_at=processed_at)

        assert generation.feature_artifact is not None
        assert generation.feature_artifact.feature_version == "v20260303-001"
        assert generation.feature_artifact.storage_path == "gs://bucket/features/v20260303-001.parquet"
        assert generation.feature_artifact.row_count == 500
        assert generation.feature_artifact.feature_count == 120

    def test_emits_completed_domain_event(self) -> None:
        generation = _make_pending_generation()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)

        generation.complete(feature_artifact=_make_artifact(), insight=_make_insight(), processed_at=processed_at)

        events = generation.domain_events
        assert len(events) == 1
        assert isinstance(events[0], FeatureGenerationCompleted)
        assert events[0].identifier == "01JNPQRS0000000000000001"
        assert events[0].feature_version == "v20260303-001"
        assert events[0].target_date == datetime.date(2026, 3, 3)
        assert events[0].trace == "trace-abc-123"

    def test_cannot_complete_from_generated(self) -> None:
        """INV-FE-005: cannot re-complete after generated."""
        generation = _make_pending_generation()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        generation.complete(feature_artifact=_make_artifact(), insight=_make_insight(), processed_at=processed_at)

        with pytest.raises(InvalidStateTransitionError):
            generation.complete(feature_artifact=_make_artifact(), insight=_make_insight(), processed_at=processed_at)

    def test_cannot_complete_from_failed(self) -> None:
        generation = _make_pending_generation()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        generation.fail(
            failure_detail=FailureDetail(
                reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE, detail=None, retryable=False
            ),
            processed_at=processed_at,
        )

        with pytest.raises(InvalidStateTransitionError):
            generation.complete(feature_artifact=_make_artifact(), insight=_make_insight(), processed_at=processed_at)


class TestFeatureGenerationFailTransition:
    def test_transition_to_failed(self) -> None:
        generation = _make_pending_generation()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        failure = FailureDetail(
            reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
            detail="JP market source returned 503",
            retryable=True,
        )

        generation.fail(failure_detail=failure, processed_at=processed_at)

        assert generation.status == FeatureGenerationStatus.FAILED
        assert generation.failure_detail is not None
        assert generation.failure_detail.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE
        assert generation.processed_at == processed_at

    def test_inv_fe_002_failed_state_has_reason_code(self) -> None:
        """INV-FE-002: failed state requires reason_code."""
        generation = _make_pending_generation()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        failure = FailureDetail(
            reason_code=ReasonCode.DATA_QUALITY_LEAK_DETECTED, detail=None, retryable=False
        )

        generation.fail(failure_detail=failure, processed_at=processed_at)

        assert generation.failure_detail is not None
        assert generation.failure_detail.reason_code == ReasonCode.DATA_QUALITY_LEAK_DETECTED

    def test_emits_failed_domain_event(self) -> None:
        generation = _make_pending_generation()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        failure = FailureDetail(
            reason_code=ReasonCode.DATA_QUALITY_LEAK_DETECTED,
            detail="Future data detected",
            retryable=False,
        )

        generation.fail(failure_detail=failure, processed_at=processed_at)

        events = generation.domain_events
        assert len(events) == 1
        assert isinstance(events[0], FeatureGenerationFailed)
        assert events[0].identifier == "01JNPQRS0000000000000001"
        assert events[0].reason_code == ReasonCode.DATA_QUALITY_LEAK_DETECTED
        assert events[0].detail == "Future data detected"

    def test_cannot_fail_from_generated(self) -> None:
        generation = _make_pending_generation()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        generation.complete(feature_artifact=_make_artifact(), insight=_make_insight(), processed_at=processed_at)

        with pytest.raises(InvalidStateTransitionError):
            generation.fail(
                failure_detail=FailureDetail(
                    reason_code=ReasonCode.STATE_CONFLICT, detail=None, retryable=False
                ),
                processed_at=processed_at,
            )

    def test_cannot_fail_from_failed(self) -> None:
        generation = _make_pending_generation()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        generation.fail(
            failure_detail=FailureDetail(
                reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE, detail=None, retryable=False
            ),
            processed_at=processed_at,
        )

        with pytest.raises(InvalidStateTransitionError):
            generation.fail(
                failure_detail=FailureDetail(
                    reason_code=ReasonCode.STATE_CONFLICT, detail=None, retryable=False
                ),
                processed_at=processed_at,
            )


class TestFeatureGenerationDomainEvents:
    def test_clear_domain_events(self) -> None:
        generation = _make_pending_generation()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        generation.complete(feature_artifact=_make_artifact(), insight=_make_insight(), processed_at=processed_at)
        assert len(generation.domain_events) == 1

        generation.clear_domain_events()
        assert generation.domain_events == []

    def test_domain_events_returns_copy(self) -> None:
        generation = _make_pending_generation()
        events = generation.domain_events
        events.append(None)  # type: ignore[arg-type]
        assert generation.domain_events == []


class TestFeatureGenerationImmutability:
    def test_inv_fe_005_identifier_immutable(self) -> None:
        """INV-FE-005: identifier is immutable after set."""
        generation = _make_pending_generation()
        with pytest.raises(AttributeError):
            generation.identifier = "changed"  # type: ignore[misc]

    def test_inv_fe_005_feature_version_immutable_after_complete(self) -> None:
        """INV-FE-005: feature_version is immutable after generated."""
        generation = _make_pending_generation()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        generation.complete(feature_artifact=_make_artifact(), insight=_make_insight(), processed_at=processed_at)

        # feature_artifact is a frozen dataclass, so its fields cannot be changed
        with pytest.raises(AttributeError):
            generation.feature_artifact.feature_version = "changed"  # type: ignore[union-attr, misc]
