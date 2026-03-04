"""Tests for domain services."""

import datetime
import inspect
from abc import ABC


class TestFeatureVersionGenerator:
    def test_is_abstract_base_class(self) -> None:
        # RULE-FE-006: featureVersion は一意採番・変更禁止のため抽象インターフェースで表現
        from domain.service.feature_version_generator import FeatureVersionGenerator

        assert issubclass(FeatureVersionGenerator, ABC)

    def test_generate_is_abstract_method(self) -> None:
        # generate() は抽象メソッドであり、実装クラスが一意採番を保証する
        from domain.service.feature_version_generator import FeatureVersionGenerator

        assert hasattr(FeatureVersionGenerator, "generate")
        assert getattr(FeatureVersionGenerator.generate, "__isabstractmethod__", False)

    def test_cannot_instantiate_directly(self) -> None:
        # 抽象クラスは直接インスタンス化できない
        from domain.service.feature_version_generator import FeatureVersionGenerator

        try:
            FeatureVersionGenerator()  # type: ignore[abstract]
            raise AssertionError("Expected TypeError was not raised")
        except TypeError:
            pass

    def test_generate_signature_accepts_target_date(self) -> None:
        # generate() は target_date を受け取り str を返す
        from domain.service.feature_version_generator import FeatureVersionGenerator

        signature = inspect.signature(FeatureVersionGenerator.generate)
        parameters = list(signature.parameters.keys())
        assert "target_date" in parameters
        assert signature.return_annotation is str


class TestPointInTimeJoinPolicy:
    def test_approve_when_snapshot_is_consistent(self) -> None:
        from domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
        from domain.value_object.insight_snapshot import InsightSnapshot

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
        from domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
        from domain.value_object.insight_snapshot import InsightSnapshot

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
        from domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
        from domain.value_object.insight_snapshot import InsightSnapshot

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
        from domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
        from domain.value_object.insight_snapshot import InsightSnapshot

        policy = PointInTimeJoinPolicy()
        target_date = datetime.date(2026, 3, 3)
        snapshot = InsightSnapshot(record_count=0, latest_collected_at=None, filtered_by_target_date=True)
        result = policy.evaluate(target_date=target_date, insight_snapshot=snapshot)
        assert result.approved is True


class TestFeatureLeakagePolicy:
    def test_no_leakage_when_consistent(self) -> None:
        from domain.service.feature_leakage_policy import FeatureLeakagePolicy
        from domain.value_object.insight_snapshot import InsightSnapshot

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
        from domain.service.feature_leakage_policy import FeatureLeakagePolicy
        from domain.value_object.enums import ReasonCode
        from domain.value_object.insight_snapshot import InsightSnapshot

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
        from domain.service.feature_leakage_policy import FeatureLeakagePolicy
        from domain.value_object.enums import ReasonCode
        from domain.value_object.insight_snapshot import InsightSnapshot

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
