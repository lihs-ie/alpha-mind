"""Tests for domain services."""

import datetime


class TestPointInTimeJoinPolicy:
    def test_approve_when_snapshot_is_consistent(self) -> None:
        from src.domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
        from src.domain.value_object.insight_snapshot import InsightSnapshot

        policy = PointInTimeJoinPolicy()
        target_date = datetime.date(2026, 3, 3)
        snapshot = InsightSnapshot(
            record_count=10,
            latest_collected_at=datetime.datetime(2026, 3, 3, 15, 0, 0, tzinfo=datetime.UTC),
            filtered_by_target_date=True,
        )
        result = policy.evaluate(target_date=target_date, insight_snapshot=snapshot)
        assert result.approved is True
        assert result.reason is None

    def test_reject_when_future_data_detected(self) -> None:
        from src.domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
        from src.domain.value_object.insight_snapshot import InsightSnapshot

        policy = PointInTimeJoinPolicy()
        target_date = datetime.date(2026, 3, 3)
        snapshot = InsightSnapshot(
            record_count=10,
            latest_collected_at=datetime.datetime(2026, 3, 4, 0, 0, 1, tzinfo=datetime.UTC),
            filtered_by_target_date=True,
        )
        result = policy.evaluate(target_date=target_date, insight_snapshot=snapshot)
        assert result.approved is False
        assert result.reason is not None

    def test_reject_when_not_filtered(self) -> None:
        from src.domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
        from src.domain.value_object.insight_snapshot import InsightSnapshot

        policy = PointInTimeJoinPolicy()
        target_date = datetime.date(2026, 3, 3)
        snapshot = InsightSnapshot(
            record_count=10,
            latest_collected_at=datetime.datetime(2026, 3, 2, 12, 0, 0, tzinfo=datetime.UTC),
            filtered_by_target_date=False,
        )
        result = policy.evaluate(target_date=target_date, insight_snapshot=snapshot)
        assert result.approved is False

    def test_approve_when_no_records(self) -> None:
        from src.domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
        from src.domain.value_object.insight_snapshot import InsightSnapshot

        policy = PointInTimeJoinPolicy()
        target_date = datetime.date(2026, 3, 3)
        snapshot = InsightSnapshot(record_count=0, latest_collected_at=None, filtered_by_target_date=True)
        result = policy.evaluate(target_date=target_date, insight_snapshot=snapshot)
        assert result.approved is True


class TestFeatureLeakagePolicy:
    def test_no_leakage_when_consistent(self) -> None:
        from src.domain.service.feature_leakage_policy import FeatureLeakagePolicy
        from src.domain.value_object.insight_snapshot import InsightSnapshot

        policy = FeatureLeakagePolicy()
        target_date = datetime.date(2026, 3, 3)
        snapshot = InsightSnapshot(
            record_count=5,
            latest_collected_at=datetime.datetime(2026, 3, 3, 12, 0, 0, tzinfo=datetime.UTC),
            filtered_by_target_date=True,
        )
        result = policy.evaluate(target_date=target_date, insight_snapshot=snapshot)
        assert result.leakage_detected is False
        assert result.reason_code is None

    def test_leakage_detected_when_future_data(self) -> None:
        from src.domain.service.feature_leakage_policy import FeatureLeakagePolicy
        from src.domain.value_object.enums import ReasonCode
        from src.domain.value_object.insight_snapshot import InsightSnapshot

        policy = FeatureLeakagePolicy()
        target_date = datetime.date(2026, 3, 3)
        snapshot = InsightSnapshot(
            record_count=5,
            latest_collected_at=datetime.datetime(2026, 3, 5, 0, 0, 0, tzinfo=datetime.UTC),
            filtered_by_target_date=True,
        )
        result = policy.evaluate(target_date=target_date, insight_snapshot=snapshot)
        assert result.leakage_detected is True
        assert result.reason_code == ReasonCode.DATA_QUALITY_LEAK_DETECTED

    def test_leakage_detected_when_not_filtered(self) -> None:
        from src.domain.service.feature_leakage_policy import FeatureLeakagePolicy
        from src.domain.value_object.enums import ReasonCode
        from src.domain.value_object.insight_snapshot import InsightSnapshot

        policy = FeatureLeakagePolicy()
        target_date = datetime.date(2026, 3, 3)
        snapshot = InsightSnapshot(
            record_count=5,
            latest_collected_at=datetime.datetime(2026, 3, 2, 12, 0, 0, tzinfo=datetime.UTC),
            filtered_by_target_date=False,
        )
        result = policy.evaluate(target_date=target_date, insight_snapshot=snapshot)
        assert result.leakage_detected is True
        assert result.reason_code == ReasonCode.DATA_QUALITY_LEAK_DETECTED
