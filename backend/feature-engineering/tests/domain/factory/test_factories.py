"""Tests for domain factories."""

import datetime

from domain.model.feature_generation import FeatureGeneration
from domain.value_object.enums import FeatureGenerationStatus, SourceStatusValue
from domain.value_object.market_snapshot import MarketSnapshot
from domain.value_object.source_status import SourceStatus


class _StubFeatureVersionGenerator:
    """Stub implementation for testing."""

    def generate(self, target_date: datetime.date) -> str:
        return f"v{target_date.strftime('%Y%m%d')}-001"


class TestFeatureGenerationFactory:
    def test_creates_pending_feature_generation(self) -> None:
        from domain.factory.feature_generation_factory import FeatureGenerationFactory
        from domain.value_object.enums import FeatureGenerationStatus, SourceStatusValue
        from domain.value_object.market_snapshot import MarketSnapshot
        from domain.value_object.source_status import SourceStatus

        factory = FeatureGenerationFactory(feature_version_generator=_StubFeatureVersionGenerator())  # type: ignore[arg-type]
        market = MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="gs://bucket/market/2026-03-03.parquet",
            source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
        )
        generation = factory.from_market_collected_event(
            identifier="01JNPQRS000000000000000001",
            market=market,
            trace="trace-abc-123",
        )

        assert generation.identifier == "01JNPQRS000000000000000001"
        assert generation.status == FeatureGenerationStatus.PENDING
        assert generation.market == market
        assert generation.trace == "trace-abc-123"
        assert generation.insight is None
        assert generation.feature_artifact is None
        assert generation.failure_detail is None
        assert generation.processed_at is None

    def test_raises_started_domain_event(self) -> None:
        from domain.event.domain_events import FeatureGenerationStarted
        from domain.factory.feature_generation_factory import FeatureGenerationFactory
        from domain.value_object.enums import SourceStatusValue
        from domain.value_object.market_snapshot import MarketSnapshot
        from domain.value_object.source_status import SourceStatus

        factory = FeatureGenerationFactory(feature_version_generator=_StubFeatureVersionGenerator())  # type: ignore[arg-type]
        market = MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="gs://bucket/path",
            source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
        )
        generation = factory.from_market_collected_event(
            identifier="01JNPQRS000000000000000001",
            market=market,
            trace="trace-abc-123",
        )

        events = generation.domain_events
        assert len(events) == 1
        assert isinstance(events[0], FeatureGenerationStarted)
        assert events[0].identifier == "01JNPQRS000000000000000001"
        assert events[0].target_date == datetime.date(2026, 3, 3)
        assert events[0].trace == "trace-abc-123"

    def test_rule_fe_001_fails_when_storage_path_empty(self) -> None:
        from domain.event.domain_events import FeatureGenerationFailed
        from domain.factory.feature_generation_factory import FeatureGenerationFactory
        from domain.value_object.enums import ReasonCode, SourceStatusValue
        from domain.value_object.market_snapshot import MarketSnapshot
        from domain.value_object.source_status import SourceStatus

        factory = FeatureGenerationFactory(feature_version_generator=_StubFeatureVersionGenerator())  # type: ignore[arg-type]
        market = MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="",
            source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
        )

        generation = factory.from_market_collected_event(
            identifier="01JNPQRS000000000000000001",
            market=market,
            trace="trace-abc-123",
        )

        assert generation.status == FeatureGenerationStatus.FAILED
        assert generation.failure_detail is not None
        assert generation.failure_detail.reason_code == ReasonCode.REQUEST_VALIDATION_FAILED
        assert generation.failure_detail.retryable is False

        # Started + Failed の2イベントが発行される
        events = generation.domain_events
        assert len(events) == 2
        assert isinstance(events[1], FeatureGenerationFailed)
        assert events[1].reason_code == ReasonCode.REQUEST_VALIDATION_FAILED

    def test_rule_fe_002_auto_fails_when_source_unhealthy(self) -> None:
        from domain.factory.feature_generation_factory import FeatureGenerationFactory
        from domain.value_object.enums import FeatureGenerationStatus, ReasonCode, SourceStatusValue
        from domain.value_object.market_snapshot import MarketSnapshot
        from domain.value_object.source_status import SourceStatus

        factory = FeatureGenerationFactory(feature_version_generator=_StubFeatureVersionGenerator())  # type: ignore[arg-type]
        market = MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="gs://bucket/market/2026-03-03.parquet",
            source_status=SourceStatus(jp=SourceStatusValue.FAILED, us=SourceStatusValue.OK),
        )
        generation = factory.from_market_collected_event(
            identifier="01JNPQRS000000000000000001",
            market=market,
            trace="trace-abc-123",
        )

        assert generation.status == FeatureGenerationStatus.FAILED
        assert generation.failure_detail is not None
        assert generation.failure_detail.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE
        assert generation.failure_detail.retryable is True

    def test_rule_fe_002_remains_pending_when_source_healthy(self) -> None:
        from domain.factory.feature_generation_factory import FeatureGenerationFactory
        from domain.value_object.enums import FeatureGenerationStatus, SourceStatusValue
        from domain.value_object.market_snapshot import MarketSnapshot
        from domain.value_object.source_status import SourceStatus

        factory = FeatureGenerationFactory(feature_version_generator=_StubFeatureVersionGenerator())  # type: ignore[arg-type]
        market = MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="gs://bucket/market/2026-03-03.parquet",
            source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
        )
        generation = factory.from_market_collected_event(
            identifier="01JNPQRS000000000000000001",
            market=market,
            trace="trace-abc-123",
        )

        assert generation.status == FeatureGenerationStatus.PENDING

    def test_generate_feature_version_delegates_to_generator(self) -> None:
        """RULE-FE-006: ファクトリが FeatureVersionGenerator.generate() を呼び出す。"""
        from domain.factory.feature_generation_factory import FeatureGenerationFactory

        generator = _StubFeatureVersionGenerator()
        factory = FeatureGenerationFactory(feature_version_generator=generator)  # type: ignore[arg-type]
        version = factory.generate_feature_version(datetime.date(2026, 3, 3))
        assert version == "v20260303-001"

    def test_feature_version_generator_produces_version(self) -> None:
        """RULE-FE-006: FeatureVersionGenerator が一意バージョンを生成する。"""
        generator = _StubFeatureVersionGenerator()
        version = generator.generate(datetime.date(2026, 3, 3))
        assert version == "v20260303-001"


def _make_generated_feature_generation() -> FeatureGeneration:
    from domain.value_object.feature_artifact import FeatureArtifact
    from domain.value_object.insight_snapshot import InsightSnapshot

    generation = FeatureGeneration(
        identifier="01JNPQRS000000000000000001",
        status=FeatureGenerationStatus.PENDING,
        market=MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="gs://bucket/market/2026-03-03.parquet",
            source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
        ),
        trace="trace-abc-123",
    )
    generation.complete(
        feature_artifact=FeatureArtifact(
            feature_version="v20260303-001",
            storage_path="gs://bucket/features/v20260303-001.parquet",
            row_count=500,
            feature_count=120,
        ),
        insight=InsightSnapshot(
            record_count=10,
            latest_collected_at=datetime.datetime(2026, 3, 3, 15, 0, 0, tzinfo=datetime.UTC),
            filtered_by_target_date=True,
        ),
        processed_at=datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC),
    )
    return generation


def _make_pending_feature_generation() -> FeatureGeneration:
    return FeatureGeneration(
        identifier="01JNPQRS000000000000000001",
        status=FeatureGenerationStatus.PENDING,
        market=MarketSnapshot(
            target_date=datetime.date(2026, 3, 3),
            storage_path="gs://bucket/market/2026-03-03.parquet",
            source_status=SourceStatus(jp=SourceStatusValue.OK, us=SourceStatusValue.OK),
        ),
        trace="trace-abc-123",
    )


class TestFeatureDispatchFactory:
    def test_creates_pending_dispatch_from_generated(self) -> None:
        from domain.factory.feature_dispatch_factory import FeatureDispatchFactory
        from domain.value_object.enums import DispatchStatus

        factory = FeatureDispatchFactory()
        generation = _make_generated_feature_generation()
        dispatch = factory.from_feature_generation(feature_generation=generation)

        assert dispatch.identifier == "01JNPQRS000000000000000001"
        assert dispatch.dispatch_status == DispatchStatus.PENDING
        assert dispatch.trace == "trace-abc-123"
        assert dispatch.published_event is None
        assert dispatch.reason_code is None
        assert dispatch.processed_at is None

    def test_creates_dispatch_with_pending_dispatch_decision(self) -> None:
        """DispatchDecision は PENDING 状態で初期化される。"""
        from domain.factory.feature_dispatch_factory import FeatureDispatchFactory
        from domain.value_object.enums import DispatchStatus

        factory = FeatureDispatchFactory()
        generation = _make_generated_feature_generation()
        dispatch = factory.from_feature_generation(feature_generation=generation)

        assert dispatch.dispatch_decision is not None
        assert dispatch.dispatch_decision.dispatch_status == DispatchStatus.PENDING
        assert dispatch.dispatch_decision.published_event is None
        assert dispatch.dispatch_decision.reason_code is None

    def test_rejects_pending_generation(self) -> None:
        import pytest

        from domain.factory.feature_dispatch_factory import FeatureDispatchFactory

        factory = FeatureDispatchFactory()
        generation = _make_pending_feature_generation()

        with pytest.raises(ValueError, match="non-terminal generation status"):
            factory.from_feature_generation(feature_generation=generation)
