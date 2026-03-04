"""Tests for domain events."""

import datetime

import pytest


class TestFeatureGenerationStarted:
    def test_create(self) -> None:
        from domain.event.domain_events import FeatureGenerationStarted

        event = FeatureGenerationStarted(
            identifier="01JNPQRS000000000000000001",
            target_date=datetime.date(2026, 3, 3),
            trace="trace-abc-123",
            occurred_at=datetime.datetime(2026, 3, 3, 12, 0, 0, tzinfo=datetime.UTC),
        )
        assert event.identifier == "01JNPQRS000000000000000001"
        assert event.target_date == datetime.date(2026, 3, 3)
        assert event.trace == "trace-abc-123"
        assert event.occurred_at == datetime.datetime(2026, 3, 3, 12, 0, 0, tzinfo=datetime.UTC)

    def test_event_type(self) -> None:
        from domain.event.domain_events import FeatureGenerationStarted

        event = FeatureGenerationStarted(
            identifier="01JNPQRS000000000000000001",
            target_date=datetime.date(2026, 3, 3),
            trace="trace-abc-123",
            occurred_at=datetime.datetime(2026, 3, 3, 12, 0, 0, tzinfo=datetime.UTC),
        )
        assert event.event_type == "feature.generation.started"

    def test_is_immutable(self) -> None:
        from domain.event.domain_events import FeatureGenerationStarted

        event = FeatureGenerationStarted(
            identifier="01JNPQRS000000000000000001",
            target_date=datetime.date(2026, 3, 3),
            trace="trace-abc-123",
            occurred_at=datetime.datetime(2026, 3, 3, 12, 0, 0, tzinfo=datetime.UTC),
        )
        with pytest.raises(AttributeError):
            event.identifier = "changed"  # type: ignore[misc]


class TestFeatureGenerationCompleted:
    def test_create(self) -> None:
        from domain.event.domain_events import FeatureGenerationCompleted

        event = FeatureGenerationCompleted(
            identifier="01JNPQRS000000000000000001",
            target_date=datetime.date(2026, 3, 3),
            feature_version="v20260303-001",
            storage_path="gs://bucket/features/v20260303-001.parquet",
            trace="trace-abc-123",
            occurred_at=datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC),
        )
        assert event.identifier == "01JNPQRS000000000000000001"
        assert event.feature_version == "v20260303-001"
        assert event.storage_path == "gs://bucket/features/v20260303-001.parquet"

    def test_event_type(self) -> None:
        from domain.event.domain_events import FeatureGenerationCompleted

        event = FeatureGenerationCompleted(
            identifier="01JNPQRS000000000000000001",
            target_date=datetime.date(2026, 3, 3),
            feature_version="v20260303-001",
            storage_path="gs://bucket/features/path",
            trace="trace-abc-123",
            occurred_at=datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC),
        )
        assert event.event_type == "feature.generation.completed"

    def test_is_immutable(self) -> None:
        from domain.event.domain_events import FeatureGenerationCompleted

        event = FeatureGenerationCompleted(
            identifier="01JNPQRS000000000000000001",
            target_date=datetime.date(2026, 3, 3),
            feature_version="v1",
            storage_path="gs://p",
            trace="t",
            occurred_at=datetime.datetime(2026, 3, 3, 12, 0, 0, tzinfo=datetime.UTC),
        )
        with pytest.raises(AttributeError):
            event.feature_version = "changed"  # type: ignore[misc]


class TestFeatureGenerationFailed:
    def test_create(self) -> None:
        from domain.event.domain_events import FeatureGenerationFailed
        from domain.value_object.enums import ReasonCode

        event = FeatureGenerationFailed(
            identifier="01JNPQRS000000000000000001",
            reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
            detail="JP source returned 503",
            trace="trace-abc-123",
            occurred_at=datetime.datetime(2026, 3, 3, 12, 0, 0, tzinfo=datetime.UTC),
        )
        assert event.identifier == "01JNPQRS000000000000000001"
        assert event.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE
        assert event.detail == "JP source returned 503"

    def test_create_without_detail(self) -> None:
        from domain.event.domain_events import FeatureGenerationFailed
        from domain.value_object.enums import ReasonCode

        event = FeatureGenerationFailed(
            identifier="01JNPQRS000000000000000001",
            reason_code=ReasonCode.STATE_CONFLICT,
            detail=None,
            trace="trace-abc-123",
            occurred_at=datetime.datetime(2026, 3, 3, 12, 0, 0, tzinfo=datetime.UTC),
        )
        assert event.detail is None

    def test_event_type(self) -> None:
        from domain.event.domain_events import FeatureGenerationFailed
        from domain.value_object.enums import ReasonCode

        event = FeatureGenerationFailed(
            identifier="01JNPQRS000000000000000001",
            reason_code=ReasonCode.DATA_QUALITY_LEAK_DETECTED,
            detail=None,
            trace="t",
            occurred_at=datetime.datetime(2026, 3, 3, 12, 0, 0, tzinfo=datetime.UTC),
        )
        assert event.event_type == "feature.generation.failed"

    def test_is_immutable(self) -> None:
        from domain.event.domain_events import FeatureGenerationFailed
        from domain.value_object.enums import ReasonCode

        event = FeatureGenerationFailed(
            identifier="01JNPQRS000000000000000001",
            reason_code=ReasonCode.DATA_QUALITY_LEAK_DETECTED,
            detail=None,
            trace="t",
            occurred_at=datetime.datetime(2026, 3, 3, 12, 0, 0, tzinfo=datetime.UTC),
        )
        with pytest.raises(AttributeError):
            event.reason_code = ReasonCode.STATE_CONFLICT  # type: ignore[misc]
