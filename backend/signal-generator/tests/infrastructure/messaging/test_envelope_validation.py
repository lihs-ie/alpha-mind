"""Tests for envelope input validation (ULID/UTC)."""

import datetime
from unittest.mock import MagicMock

import pytest

from signal_generator.domain.enums.degradation_flag import DegradationFlag
from signal_generator.domain.events.signal_generation_completed_event import (
    SignalGenerationCompletedEvent,
)
from signal_generator.domain.value_objects.model_diagnostics_snapshot import (
    ModelDiagnosticsSnapshot,
)
from signal_generator.infrastructure.messaging.pubsub_signal_event_publisher import (
    PubSubSignalEventPublisher,
)


def _make_publisher() -> PubSubSignalEventPublisher:
    mock_publisher_client = MagicMock()
    future = MagicMock()
    future.result.return_value = "message-id"
    mock_publisher_client.publish.return_value = future
    return PubSubSignalEventPublisher(
        publisher_client=mock_publisher_client,
        project_id="test-project",
    )


def _make_event(
    identifier: str = "01JTEST0000000000000000000",
    trace: str = "01JTRACE000000000000000000",
    occurred_at: datetime.datetime | None = None,
) -> SignalGenerationCompletedEvent:
    if occurred_at is None:
        occurred_at = datetime.datetime(2026, 3, 5, 10, 30, 0, tzinfo=datetime.UTC)
    return SignalGenerationCompletedEvent(
        identifier=identifier,
        signal_version="sv-20260305",
        model_version="v1.0.0",
        feature_version="fv-20260305",
        storage_path="gs://bucket/signals/2026-03-05.parquet",
        model_diagnostics=ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        ),
        trace=trace,
        occurred_at=occurred_at,
    )


class TestEnvelopeValidation:
    """エンベロープ入力の ULID/UTC バリデーションテスト。"""

    def test_invalid_identifier_raises_value_error(self) -> None:
        publisher = _make_publisher()
        with pytest.raises(ValueError, match="identifier must be a valid ULID"):
            publisher.publish_signal_generated(_make_event(identifier="invalid-ulid"))

    def test_invalid_trace_raises_value_error(self) -> None:
        publisher = _make_publisher()
        with pytest.raises(ValueError, match="trace must be a valid ULID"):
            publisher.publish_signal_generated(_make_event(trace="not-a-ulid"))

    def test_naive_datetime_raises_value_error(self) -> None:
        publisher = _make_publisher()
        naive_dt = datetime.datetime(2026, 3, 5, 10, 30, 0)
        with pytest.raises(ValueError, match="timezone-aware"):
            publisher.publish_signal_generated(_make_event(occurred_at=naive_dt))

    def test_valid_ulid_and_utc_succeeds(self) -> None:
        publisher = _make_publisher()
        publisher.publish_signal_generated(_make_event())
