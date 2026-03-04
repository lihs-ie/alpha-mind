"""Tests for domain specifications."""

import datetime


class TestMarketPayloadIntegritySpecification:
    def test_satisfied_when_all_fields_present(self) -> None:
        from domain.specification.market_payload_integrity import MarketPayloadIntegritySpecification
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.market_snapshot import MarketSnapshot
        from domain.value_object.source_status import SourceStatus

        specification = MarketPayloadIntegritySpecification()
        snapshot = MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="gs://bucket/market/2026-03-03.parquet",
            source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
        )
        assert specification.is_satisfied_by(snapshot) is True

    def test_not_satisfied_when_storage_path_empty(self) -> None:
        from domain.specification.market_payload_integrity import MarketPayloadIntegritySpecification
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.market_snapshot import MarketSnapshot
        from domain.value_object.source_status import SourceStatus

        specification = MarketPayloadIntegritySpecification()
        snapshot = MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="",
            source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
        )
        assert specification.is_satisfied_by(snapshot) is False


class TestSourceStatusHealthySpecification:
    def test_satisfied_when_both_ok(self) -> None:
        from domain.specification.source_status_healthy import SourceStatusHealthySpecification
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.source_status import SourceStatus

        specification = SourceStatusHealthySpecification()
        status = SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK)
        assert specification.is_satisfied_by(status) is True

    def test_not_satisfied_when_jp_failed(self) -> None:
        from domain.specification.source_status_healthy import SourceStatusHealthySpecification
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.source_status import SourceStatus

        specification = SourceStatusHealthySpecification()
        status = SourceStatus(jp=SourceStatusValue.FAILED, us=SourceStatusValue.OK)
        assert specification.is_satisfied_by(status) is False

    def test_not_satisfied_when_us_failed(self) -> None:
        from domain.specification.source_status_healthy import SourceStatusHealthySpecification
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.source_status import SourceStatus

        specification = SourceStatusHealthySpecification()
        status = SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.FAILED)
        assert specification.is_satisfied_by(status) is False

    def test_not_satisfied_when_both_failed(self) -> None:
        from domain.specification.source_status_healthy import SourceStatusHealthySpecification
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.source_status import SourceStatus

        specification = SourceStatusHealthySpecification()
        status = SourceStatus(jp=SourceStatusValue.FAILED, us=SourceStatusValue.FAILED)
        assert specification.is_satisfied_by(status) is False


class TestPointInTimeConsistencySpecification:
    def test_satisfied_when_latest_collected_at_before_target_date(self) -> None:
        from domain.specification.point_in_time_consistency import PointInTimeConsistencySpecification
        from domain.value_object.insight_snapshot import InsightSnapshot

        specification = PointInTimeConsistencySpecification(target_date=datetime.date(2026, 3, 3))
        snapshot = InsightSnapshot(
            record_count=10,
            latest_collected_at=datetime.datetime(2026, 3, 2, 23, 59, 59, tzinfo=datetime.UTC),
            filtered_by_target_date=True,
        )
        assert specification.is_satisfied_by(snapshot) is True

    def test_satisfied_when_latest_collected_at_equals_target_date_end_of_day(self) -> None:
        from domain.specification.point_in_time_consistency import PointInTimeConsistencySpecification
        from domain.value_object.insight_snapshot import InsightSnapshot

        specification = PointInTimeConsistencySpecification(target_date=datetime.date(2026, 3, 3))
        # End of target_date (23:59:59 UTC) should be valid
        snapshot = InsightSnapshot(
            record_count=10,
            latest_collected_at=datetime.datetime(2026, 3, 3, 23, 59, 59, tzinfo=datetime.UTC),
            filtered_by_target_date=True,
        )
        assert specification.is_satisfied_by(snapshot) is True

    def test_not_satisfied_when_latest_collected_at_after_target_date(self) -> None:
        from domain.specification.point_in_time_consistency import PointInTimeConsistencySpecification
        from domain.value_object.insight_snapshot import InsightSnapshot

        specification = PointInTimeConsistencySpecification(target_date=datetime.date(2026, 3, 3))
        snapshot = InsightSnapshot(
            record_count=10,
            latest_collected_at=datetime.datetime(2026, 3, 4, 0, 0, 1, tzinfo=datetime.UTC),
            filtered_by_target_date=True,
        )
        assert specification.is_satisfied_by(snapshot) is False

    def test_satisfied_when_no_records(self) -> None:
        from domain.specification.point_in_time_consistency import PointInTimeConsistencySpecification
        from domain.value_object.insight_snapshot import InsightSnapshot

        specification = PointInTimeConsistencySpecification(target_date=datetime.date(2026, 3, 3))
        snapshot = InsightSnapshot(
            record_count=0,
            latest_collected_at=None,
            filtered_by_target_date=True,
        )
        assert specification.is_satisfied_by(snapshot) is True

    def test_not_satisfied_when_not_filtered_by_target_date(self) -> None:
        from domain.specification.point_in_time_consistency import PointInTimeConsistencySpecification
        from domain.value_object.insight_snapshot import InsightSnapshot

        specification = PointInTimeConsistencySpecification(target_date=datetime.date(2026, 3, 3))
        snapshot = InsightSnapshot(
            record_count=10,
            latest_collected_at=datetime.datetime(2026, 3, 2, 12, 0, 0, tzinfo=datetime.UTC),
            filtered_by_target_date=False,
        )
        assert specification.is_satisfied_by(snapshot) is False
