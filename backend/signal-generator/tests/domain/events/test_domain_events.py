"""Tests for domain event types."""

import datetime
from dataclasses import FrozenInstanceError

import pytest

from signal_generator.domain.enums.degradation_flag import DegradationFlag
from signal_generator.domain.enums.event_type import EventType
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.events.signal_generation_completed_event import SignalGenerationCompletedEvent
from signal_generator.domain.events.signal_generation_failed_event import SignalGenerationFailedEvent
from signal_generator.domain.events.signal_generation_started_event import SignalGenerationStartedEvent
from signal_generator.domain.value_objects.model_diagnostics_snapshot import ModelDiagnosticsSnapshot


class TestSignalGenerationStartedEvent:
    def test_create_event(self) -> None:
        event = SignalGenerationStartedEvent(
            identifier="01JNABCDEF1234567890123456",
            feature_version="v1.0.0",
            trace="trace-001",
            occurred_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        )
        assert event.identifier == "01JNABCDEF1234567890123456"
        assert event.feature_version == "v1.0.0"
        assert event.trace == "trace-001"
        assert event.event_type == EventType.SIGNAL_GENERATION_STARTED

    def test_immutability(self) -> None:
        event = SignalGenerationStartedEvent(
            identifier="01JNABCDEF1234567890123456",
            feature_version="v1.0.0",
            trace="trace-001",
            occurred_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        )
        with pytest.raises(FrozenInstanceError):
            event.identifier = "new-id"  # type: ignore[misc]


class TestSignalGenerationCompletedEvent:
    def test_create_event(self) -> None:
        diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        )
        event = SignalGenerationCompletedEvent(
            identifier="01JNABCDEF1234567890123456",
            signal_version="signal-v1.0.0",
            model_version="model-v1.0.0",
            feature_version="v1.0.0",
            storage_path="gs://signal_store/2026-01-01/signals.parquet",
            model_diagnostics=diagnostics,
            trace="trace-001",
            occurred_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        )
        assert event.identifier == "01JNABCDEF1234567890123456"
        assert event.signal_version == "signal-v1.0.0"
        assert event.model_version == "model-v1.0.0"
        assert event.feature_version == "v1.0.0"
        assert event.storage_path == "gs://signal_store/2026-01-01/signals.parquet"
        assert event.model_diagnostics == diagnostics
        assert event.event_type == EventType.SIGNAL_GENERATION_COMPLETED

    def test_model_diagnostics_is_required(self) -> None:
        # RULE-SG-006: modelDiagnostics は必須
        with pytest.raises(TypeError):
            SignalGenerationCompletedEvent(  # type: ignore[call-arg]
                identifier="01JNABCDEF1234567890123456",
                signal_version="signal-v1.0.0",
                model_version="model-v1.0.0",
                feature_version="v1.0.0",
                storage_path="gs://signal_store/2026-01-01/signals.parquet",
                trace="trace-001",
                occurred_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
            )

    def test_immutability(self) -> None:
        diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        )
        event = SignalGenerationCompletedEvent(
            identifier="01JNABCDEF1234567890123456",
            signal_version="signal-v1.0.0",
            model_version="model-v1.0.0",
            feature_version="v1.0.0",
            storage_path="gs://signal_store/2026-01-01/signals.parquet",
            model_diagnostics=diagnostics,
            trace="trace-001",
            occurred_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        )
        with pytest.raises(FrozenInstanceError):
            event.signal_version = "new-version"  # type: ignore[misc]


class TestSignalGenerationFailedEvent:
    def test_create_event(self) -> None:
        event = SignalGenerationFailedEvent(
            identifier="01JNABCDEF1234567890123456",
            reason_code=ReasonCode.MODEL_NOT_APPROVED,
            trace="trace-001",
            occurred_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        )
        assert event.identifier == "01JNABCDEF1234567890123456"
        assert event.reason_code == ReasonCode.MODEL_NOT_APPROVED
        assert event.trace == "trace-001"
        assert event.event_type == EventType.SIGNAL_GENERATION_FAILED
        assert event.detail is None

    def test_create_event_with_detail(self) -> None:
        event = SignalGenerationFailedEvent(
            identifier="01JNABCDEF1234567890123456",
            reason_code=ReasonCode.DEPENDENCY_TIMEOUT,
            trace="trace-001",
            occurred_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
            detail="MLflow connection timed out",
        )
        assert event.detail == "MLflow connection timed out"

    def test_immutability(self) -> None:
        event = SignalGenerationFailedEvent(
            identifier="01JNABCDEF1234567890123456",
            reason_code=ReasonCode.MODEL_NOT_APPROVED,
            trace="trace-001",
            occurred_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        )
        with pytest.raises(FrozenInstanceError):
            event.reason_code = ReasonCode.STATE_CONFLICT  # type: ignore[misc]
