"""Tests for domain factories."""

import datetime


class TestFeatureGenerationFactory:
    def test_creates_pending_feature_generation(self) -> None:
        from src.domain.factory.feature_generation_factory import FeatureGenerationFactory
        from src.domain.value_object.enums import FeatureGenerationStatus, SourceStatusValue
        from src.domain.value_object.market_snapshot import MarketSnapshot
        from src.domain.value_object.source_status import SourceStatus

        factory = FeatureGenerationFactory()
        market = MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="gs://bucket/market/2026-03-03.parquet",
            source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
        )
        generation = factory.from_market_collected_event(
            identifier="01JNPQRS0000000000000001",
            market=market,
            trace="trace-abc-123",
        )

        assert generation.identifier == "01JNPQRS0000000000000001"
        assert generation.status == FeatureGenerationStatus.PENDING
        assert generation.market == market
        assert generation.trace == "trace-abc-123"
        assert generation.insight is None
        assert generation.feature_artifact is None
        assert generation.failure_detail is None
        assert generation.processed_at is None

    def test_raises_started_domain_event(self) -> None:
        from src.domain.event.domain_events import FeatureGenerationStarted
        from src.domain.factory.feature_generation_factory import FeatureGenerationFactory
        from src.domain.value_object.enums import SourceStatusValue
        from src.domain.value_object.market_snapshot import MarketSnapshot
        from src.domain.value_object.source_status import SourceStatus

        factory = FeatureGenerationFactory()
        market = MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="gs://bucket/path",
            source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
        )
        generation = factory.from_market_collected_event(
            identifier="01JNPQRS0000000000000001",
            market=market,
            trace="trace-abc-123",
        )

        events = generation.domain_events
        assert len(events) == 1
        assert isinstance(events[0], FeatureGenerationStarted)
        assert events[0].identifier == "01JNPQRS0000000000000001"
        assert events[0].target_date == datetime.date(2026, 3, 3)
        assert events[0].trace == "trace-abc-123"


class TestFeatureDispatchFactory:
    def test_creates_pending_dispatch(self) -> None:
        from src.domain.factory.feature_dispatch_factory import FeatureDispatchFactory
        from src.domain.value_object.enums import DispatchStatus

        factory = FeatureDispatchFactory()
        dispatch = factory.from_feature_generation(
            identifier="01JNPQRS0000000000000001",
            trace="trace-abc-123",
        )

        assert dispatch.identifier == "01JNPQRS0000000000000001"
        assert dispatch.dispatch_status == DispatchStatus.PENDING
        assert dispatch.trace == "trace-abc-123"
        assert dispatch.published_event is None
        assert dispatch.reason_code is None
        assert dispatch.processed_at is None
