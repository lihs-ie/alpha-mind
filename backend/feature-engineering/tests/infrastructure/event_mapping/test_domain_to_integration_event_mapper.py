"""Tests for DomainToIntegrationEventMapper."""

import datetime

from domain.event.domain_events import FeatureGenerationCompleted, FeatureGenerationFailed
from domain.value_object.enums import ReasonCode
from infrastructure.event_mapping.domain_to_integration_event_mapper import (
    DomainToIntegrationEventMapper,
)

VALID_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
VALID_TRACE = "01ARZ3NDEKTSV4RRFFQ69G5FAW"


class TestMapFeatureGenerationCompleted:
    def test_maps_to_features_generated_envelope(self) -> None:
        event = FeatureGenerationCompleted(
            identifier=VALID_ULID,
            target_date=datetime.date(2026, 1, 15),
            feature_version="v20260115-001",
            storage_path="gs://feature_store/v20260115-001/features.parquet",
            trace=VALID_TRACE,
            occurred_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        )

        envelope = DomainToIntegrationEventMapper.map(event)

        assert envelope["identifier"] == VALID_ULID
        assert envelope["eventType"] == "features.generated"
        assert envelope["occurredAt"] == "2026-01-15T09:00:00Z"
        assert envelope["trace"] == VALID_TRACE
        assert envelope["schemaVersion"] == "1.0.0"
        assert envelope["payload"]["targetDate"] == "2026-01-15"
        assert envelope["payload"]["featureVersion"] == "v20260115-001"
        assert envelope["payload"]["storagePath"] == "gs://feature_store/v20260115-001/features.parquet"


class TestMapFeatureGenerationFailed:
    def test_maps_to_features_generation_failed_envelope(self) -> None:
        event = FeatureGenerationFailed(
            identifier=VALID_ULID,
            reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
            detail="US market data unavailable",
            trace=VALID_TRACE,
            occurred_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        )

        envelope = DomainToIntegrationEventMapper.map(event)

        assert envelope["identifier"] == VALID_ULID
        assert envelope["eventType"] == "features.generation.failed"
        assert envelope["occurredAt"] == "2026-01-15T09:00:00Z"
        assert envelope["trace"] == VALID_TRACE
        assert envelope["schemaVersion"] == "1.0.0"
        assert envelope["payload"]["reasonCode"] == "DEPENDENCY_UNAVAILABLE"
        assert envelope["payload"]["detail"] == "US market data unavailable"

    def test_maps_failed_event_with_none_detail(self) -> None:
        event = FeatureGenerationFailed(
            identifier=VALID_ULID,
            reason_code=ReasonCode.FEATURE_GENERATION_FAILED,
            detail=None,
            trace=VALID_TRACE,
            occurred_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        )

        envelope = DomainToIntegrationEventMapper.map(event)

        assert envelope["payload"]["reasonCode"] == "FEATURE_GENERATION_FAILED"
        assert envelope["payload"]["detail"] is None


class TestReasonCodeValidation:
    def test_map_failed_rejects_unknown_reason_code(self) -> None:
        import pytest

        event = FeatureGenerationFailed(
            identifier=VALID_ULID,
            reason_code=ReasonCode.DISPATCH_FAILED,
            detail="dispatch error",
            trace=VALID_TRACE,
            occurred_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        )

        with pytest.raises(
            ValueError,
            match="reasonCode 'DISPATCH_FAILED' is not defined in AsyncAPI contract",
        ):
            DomainToIntegrationEventMapper.map(event)


class TestUnsupportedEventType:
    def test_raises_for_unknown_event(self) -> None:
        import pytest

        class UnknownEvent:
            pass

        with pytest.raises(ValueError, match="Unsupported domain event type"):
            DomainToIntegrationEventMapper.map(UnknownEvent())  # type: ignore[arg-type]


class TestUtcFormatValidation:
    def test_map_raises_for_naive_datetime(self) -> None:
        import pytest

        event = FeatureGenerationCompleted(
            identifier=VALID_ULID,
            target_date=datetime.date(2026, 1, 15),
            feature_version="v20260115-001",
            storage_path="gs://feature_store/v20260115-001/features.parquet",
            trace=VALID_TRACE,
            occurred_at=datetime.datetime(2026, 1, 15, 9, 0, 0),  # naive
        )

        with pytest.raises(ValueError, match="occurred_at must be timezone-aware"):
            DomainToIntegrationEventMapper.map(event)

    def test_map_normalizes_non_utc_timezone(self) -> None:
        jst = datetime.timezone(datetime.timedelta(hours=9))
        event = FeatureGenerationCompleted(
            identifier=VALID_ULID,
            target_date=datetime.date(2026, 1, 15),
            feature_version="v20260115-001",
            storage_path="gs://feature_store/v20260115-001/features.parquet",
            trace=VALID_TRACE,
            occurred_at=datetime.datetime(2026, 1, 15, 18, 0, 0, tzinfo=jst),  # 18:00 JST = 09:00 UTC
        )

        envelope = DomainToIntegrationEventMapper.map(event)

        assert envelope["occurredAt"] == "2026-01-15T09:00:00Z"
