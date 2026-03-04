"""Tests for Factory implementations."""

import datetime

from signal_generator.domain.aggregates.signal_generation import SignalGeneration
from signal_generator.domain.enums.dispatch_status import DispatchStatus
from signal_generator.domain.enums.generation_status import GenerationStatus
from signal_generator.domain.factories.signal_dispatch_factory import SignalDispatchFactory
from signal_generator.domain.factories.signal_generation_factory import SignalGenerationFactory
from signal_generator.domain.value_objects.feature_snapshot import FeatureSnapshot


class TestSignalGenerationFactory:
    def test_create_from_features_generated_event(self) -> None:
        factory = SignalGenerationFactory()
        feature_snapshot = FeatureSnapshot(
            target_date=datetime.date(2026, 1, 1),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-01-01/features.parquet",
        )
        generation = factory.from_features_generated_event(
            identifier="01JNABCDEF1234567890123456",
            feature_snapshot=feature_snapshot,
            universe_count=100,
            trace="trace-001",
        )

        assert isinstance(generation, SignalGeneration)
        assert generation.identifier == "01JNABCDEF1234567890123456"
        assert generation.status == GenerationStatus.PENDING
        assert generation.feature_snapshot == feature_snapshot
        assert generation.universe_count == 100
        assert generation.trace == "trace-001"

    def test_created_generation_starts_pending(self) -> None:
        factory = SignalGenerationFactory()
        feature_snapshot = FeatureSnapshot(
            target_date=datetime.date(2026, 1, 1),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-01-01/features.parquet",
        )
        generation = factory.from_features_generated_event(
            identifier="01JNABCDEF1234567890123456",
            feature_snapshot=feature_snapshot,
            universe_count=100,
            trace="trace-001",
        )
        assert generation.model_snapshot is None
        assert generation.signal_artifact is None
        assert generation.failure_detail is None


class TestSignalDispatchFactory:
    def test_create_from_signal_generation_identifiers(self) -> None:
        factory = SignalDispatchFactory()

        dispatch = factory.from_signal_generation(
            identifier="01JNABCDEF1234567890123456",
            trace="trace-001",
        )

        assert dispatch.identifier == "01JNABCDEF1234567890123456"
        assert dispatch.dispatch_status == DispatchStatus.PENDING
        assert dispatch.trace == "trace-001"

    def test_dispatch_shares_identifier_with_generation(self) -> None:
        # SignalDispatch は SignalGeneration と同じ identifier を使う (冪等性キーとして共有)
        factory = SignalDispatchFactory()
        feature_snapshot = FeatureSnapshot(
            target_date=datetime.date(2026, 1, 1),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-01-01/features.parquet",
        )
        signal_generation = SignalGeneration(
            identifier="01JNABCDEF1234567890123456",
            feature_snapshot=feature_snapshot,
            universe_count=100,
            trace="trace-001",
        )
        dispatch = factory.from_signal_generation(
            identifier=signal_generation.identifier,
            trace=signal_generation.trace,
        )

        assert dispatch.identifier == signal_generation.identifier
