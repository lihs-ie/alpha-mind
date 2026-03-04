"""Tests for domain value objects."""

import datetime

import pytest


class TestSourceStatus:
    def test_create_with_both_ok(self) -> None:
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.source_status import SourceStatus

        status = SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK)
        assert status.jp == SourceStatusValue.OK
        assert status.us == SourceStatusValue.OK

    def test_is_immutable(self) -> None:
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.source_status import SourceStatus

        status = SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK)
        with pytest.raises(AttributeError):
            status.jp = SourceStatusValue.FAILED  # type: ignore[misc]

    def test_equality_by_value(self) -> None:
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.source_status import SourceStatus

        status_a = SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK)
        status_b = SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK)
        assert status_a == status_b

    def test_inequality_when_different(self) -> None:
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.source_status import SourceStatus

        status_a = SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK)
        status_b = SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.FAILED)
        assert status_a != status_b


class TestMarketSnapshot:
    def test_create(self) -> None:
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.market_snapshot import MarketSnapshot
        from domain.value_object.source_status import SourceStatus

        target_date = datetime.date(2026, 3, 3)
        source_status = SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK)
        snapshot = MarketSnapshot(
            target_date=target_date,
            storage_path="gs://bucket/market/2026-03-03.parquet",
            source_status=source_status,
        )
        assert snapshot.target_date == target_date
        assert snapshot.storage_path == "gs://bucket/market/2026-03-03.parquet"
        assert snapshot.source_status == source_status

    def test_is_immutable(self) -> None:
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.market_snapshot import MarketSnapshot
        from domain.value_object.source_status import SourceStatus

        snapshot = MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="gs://bucket/path",
            source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
        )
        with pytest.raises(AttributeError):
            snapshot.target_date = datetime.date(2026, 3, 4)  # type: ignore[misc]

    def test_equality_by_value(self) -> None:
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.market_snapshot import MarketSnapshot
        from domain.value_object.source_status import SourceStatus

        source_status = SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK)
        snapshot_a = MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="gs://bucket/path",
            source_status=source_status,
        )
        snapshot_b = MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="gs://bucket/path",
            source_status=source_status,
        )
        assert snapshot_a == snapshot_b


class TestInsightSnapshot:
    def test_create_with_records(self) -> None:
        from domain.value_object.insight_snapshot import InsightSnapshot

        latest = datetime.datetime(2026, 3, 3, 10, 0, 0, tzinfo=datetime.UTC)
        snapshot = InsightSnapshot(
            record_count=42,
            latest_collected_at=latest,
            filtered_by_target_date=True,
        )
        assert snapshot.record_count == 42
        assert snapshot.latest_collected_at == latest
        assert snapshot.filtered_by_target_date is True

    def test_create_with_no_records(self) -> None:
        from domain.value_object.insight_snapshot import InsightSnapshot

        snapshot = InsightSnapshot(
            record_count=0,
            latest_collected_at=None,
            filtered_by_target_date=True,
        )
        assert snapshot.record_count == 0
        assert snapshot.latest_collected_at is None

    def test_is_immutable(self) -> None:
        from domain.value_object.insight_snapshot import InsightSnapshot

        snapshot = InsightSnapshot(record_count=1, latest_collected_at=None, filtered_by_target_date=True)
        with pytest.raises(AttributeError):
            snapshot.record_count = 99  # type: ignore[misc]

    def test_rejects_negative_record_count(self) -> None:
        from domain.value_object.insight_snapshot import InsightSnapshot

        with pytest.raises(ValueError, match="record_count must be non-negative"):
            InsightSnapshot(record_count=-1, latest_collected_at=None, filtered_by_target_date=True)

    def test_rejects_naive_datetime(self) -> None:
        from domain.value_object.insight_snapshot import InsightSnapshot

        with pytest.raises(ValueError, match="latest_collected_at must be timezone-aware"):
            InsightSnapshot(
                record_count=1,
                latest_collected_at=datetime.datetime(2026, 3, 3, 12, 0, 0),
                filtered_by_target_date=True,
            )


class TestFeatureArtifact:
    def test_create(self) -> None:
        from domain.value_object.feature_artifact import FeatureArtifact

        artifact = FeatureArtifact(
            feature_version="v20260303-001",
            storage_path="gs://bucket/features/v20260303-001.parquet",
            row_count=500,
            feature_count=120,
        )
        assert artifact.feature_version == "v20260303-001"
        assert artifact.storage_path == "gs://bucket/features/v20260303-001.parquet"
        assert artifact.row_count == 500
        assert artifact.feature_count == 120

    def test_is_immutable(self) -> None:
        from domain.value_object.feature_artifact import FeatureArtifact

        artifact = FeatureArtifact(
            feature_version="v1",
            storage_path="gs://bucket/path",
            row_count=10,
            feature_count=5,
        )
        with pytest.raises(AttributeError):
            artifact.row_count = 999  # type: ignore[misc]

    def test_equality_by_value(self) -> None:
        from domain.value_object.feature_artifact import FeatureArtifact

        artifact_a = FeatureArtifact(feature_version="v1", storage_path="gs://p", row_count=10, feature_count=5)
        artifact_b = FeatureArtifact(feature_version="v1", storage_path="gs://p", row_count=10, feature_count=5)
        assert artifact_a == artifact_b

    def test_rejects_empty_feature_version(self) -> None:
        from domain.value_object.feature_artifact import FeatureArtifact

        with pytest.raises(ValueError, match="feature_version must not be empty"):
            FeatureArtifact(feature_version="", storage_path="gs://p", row_count=10, feature_count=5)

    def test_rejects_empty_storage_path(self) -> None:
        from domain.value_object.feature_artifact import FeatureArtifact

        with pytest.raises(ValueError, match="storage_path must not be empty"):
            FeatureArtifact(feature_version="v1", storage_path="", row_count=10, feature_count=5)

    def test_rejects_negative_row_count(self) -> None:
        from domain.value_object.feature_artifact import FeatureArtifact

        with pytest.raises(ValueError, match="row_count must be non-negative"):
            FeatureArtifact(feature_version="v1", storage_path="gs://p", row_count=-1, feature_count=5)

    def test_rejects_negative_feature_count(self) -> None:
        from domain.value_object.feature_artifact import FeatureArtifact

        with pytest.raises(ValueError, match="feature_count must be non-negative"):
            FeatureArtifact(feature_version="v1", storage_path="gs://p", row_count=10, feature_count=-1)


class TestFailureDetail:
    def test_create(self) -> None:
        from domain.value_object.enums import ReasonCode
        from domain.value_object.failure_detail import FailureDetail

        detail = FailureDetail(
            reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
            detail="JP market source returned error",
            retryable=True,
        )
        assert detail.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE
        assert detail.detail == "JP market source returned error"
        assert detail.retryable is True

    def test_create_without_detail_text(self) -> None:
        from domain.value_object.enums import ReasonCode
        from domain.value_object.failure_detail import FailureDetail

        detail = FailureDetail(
            reason_code=ReasonCode.DATA_QUALITY_LEAK_DETECTED,
            detail=None,
            retryable=False,
        )
        assert detail.detail is None

    def test_is_immutable(self) -> None:
        from domain.value_object.enums import ReasonCode
        from domain.value_object.failure_detail import FailureDetail

        detail = FailureDetail(reason_code=ReasonCode.STATE_CONFLICT, detail=None, retryable=False)
        with pytest.raises(AttributeError):
            detail.retryable = True  # type: ignore[misc]

    def test_rejects_none_reason_code(self) -> None:
        from domain.value_object.failure_detail import FailureDetail

        with pytest.raises(ValueError, match="reason_code must not be None"):
            FailureDetail(reason_code=None, detail=None, retryable=False)  # type: ignore[arg-type]


class TestDispatchDecision:
    def test_create_published(self) -> None:
        from domain.value_object.dispatch_decision import DispatchDecision
        from domain.value_object.enums import DispatchStatus, PublishedEventType

        decision = DispatchDecision(
            dispatch_status=DispatchStatus.PUBLISHED,
            published_event=PublishedEventType.FEATURES_GENERATED,
            reason_code=None,
        )
        assert decision.dispatch_status == DispatchStatus.PUBLISHED
        assert decision.published_event == PublishedEventType.FEATURES_GENERATED
        assert decision.reason_code is None

    def test_create_failed(self) -> None:
        from domain.value_object.dispatch_decision import DispatchDecision
        from domain.value_object.enums import DispatchStatus, ReasonCode

        decision = DispatchDecision(
            dispatch_status=DispatchStatus.FAILED,
            published_event=None,
            reason_code=ReasonCode.DISPATCH_FAILED,
        )
        assert decision.dispatch_status == DispatchStatus.FAILED
        assert decision.published_event is None
        assert decision.reason_code == ReasonCode.DISPATCH_FAILED

    def test_is_immutable(self) -> None:
        from domain.value_object.dispatch_decision import DispatchDecision
        from domain.value_object.enums import DispatchStatus

        decision = DispatchDecision(dispatch_status=DispatchStatus.PENDING, published_event=None, reason_code=None)
        with pytest.raises(AttributeError):
            decision.dispatch_status = DispatchStatus.PUBLISHED  # type: ignore[misc]
