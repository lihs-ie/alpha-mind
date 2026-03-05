"""Tests for SignalDispatch aggregate root."""

import datetime

import pytest

from signal_generator.domain.aggregates.signal_dispatch import SignalDispatch
from signal_generator.domain.enums.dispatch_status import DispatchStatus
from signal_generator.domain.enums.event_type import EventType
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.value_objects.dispatch_decision import DispatchDecision


class TestSignalDispatchCreation:
    def test_create_pending_dispatch(self) -> None:
        dispatch = SignalDispatch(
            identifier="01JNABCDEF1234567890123456",
            trace="trace-001",
        )
        assert dispatch.identifier == "01JNABCDEF1234567890123456"
        assert dispatch.dispatch_status == DispatchStatus.PENDING
        assert dispatch.trace == "trace-001"
        assert dispatch.published_event is None
        assert dispatch.reason_code is None
        assert dispatch.processed_at is None


class TestSignalDispatchPublish:
    def test_publish_from_pending(self) -> None:
        dispatch = SignalDispatch(
            identifier="01JNABCDEF1234567890123456",
            trace="trace-001",
        )
        processed_at = datetime.datetime(2026, 1, 1, 10, 0, 0, tzinfo=datetime.UTC)
        dispatch.publish(published_event=EventType.SIGNAL_GENERATED, processed_at=processed_at)

        assert dispatch.dispatch_status == DispatchStatus.PUBLISHED
        assert dispatch.published_event == EventType.SIGNAL_GENERATED
        assert dispatch.processed_at == processed_at

    def test_publish_twice_raises_error(self) -> None:
        # INV-SG-004: 同一イベント identifier は1回のみ publish
        dispatch = SignalDispatch(
            identifier="01JNABCDEF1234567890123456",
            trace="trace-001",
        )
        processed_at = datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC)
        dispatch.publish(published_event=EventType.SIGNAL_GENERATED, processed_at=processed_at)

        with pytest.raises(ValueError, match="IDEMPOTENCY_DUPLICATE_EVENT"):
            dispatch.publish(published_event=EventType.SIGNAL_GENERATED, processed_at=processed_at)

    def test_publish_internal_event_raises_error(self) -> None:
        dispatch = SignalDispatch(
            identifier="01JNABCDEF1234567890123456",
            trace="trace-001",
        )
        with pytest.raises(ValueError, match="境界内ドメインイベント"):
            dispatch.publish(
                published_event=EventType.SIGNAL_GENERATION_STARTED,
                processed_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
            )

    def test_publish_from_failed_raises_state_conflict(self) -> None:
        dispatch = SignalDispatch(
            identifier="01JNABCDEF1234567890123456",
            trace="trace-001",
        )
        processed_at = datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC)
        dispatch.fail(reason_code=ReasonCode.DEPENDENCY_TIMEOUT, processed_at=processed_at)

        with pytest.raises(ValueError, match="STATE_CONFLICT"):
            dispatch.publish(
                published_event=EventType.SIGNAL_GENERATED,
                processed_at=processed_at,
            )

    def test_publish_signal_generation_failed_is_allowed(self) -> None:
        dispatch = SignalDispatch(
            identifier="01JNABCDEF1234567890123456",
            trace="trace-001",
        )
        dispatch.publish(
            published_event=EventType.SIGNAL_GENERATION_FAILED,
            processed_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        )
        assert dispatch.dispatch_status == DispatchStatus.PUBLISHED
        assert dispatch.published_event == EventType.SIGNAL_GENERATION_FAILED


class TestSignalDispatchFail:
    def test_fail_from_pending(self) -> None:
        dispatch = SignalDispatch(
            identifier="01JNABCDEF1234567890123456",
            trace="trace-001",
        )
        processed_at = datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC)
        dispatch.fail(reason_code=ReasonCode.DEPENDENCY_TIMEOUT, processed_at=processed_at)

        assert dispatch.dispatch_status == DispatchStatus.FAILED
        assert dispatch.reason_code == ReasonCode.DEPENDENCY_TIMEOUT
        assert dispatch.processed_at == processed_at

    def test_fail_on_published_raises_state_conflict(self) -> None:
        dispatch = SignalDispatch(
            identifier="01JNABCDEF1234567890123456",
            trace="trace-001",
        )
        processed_at = datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC)
        dispatch.publish(published_event=EventType.SIGNAL_GENERATED, processed_at=processed_at)

        with pytest.raises(ValueError, match="STATE_CONFLICT"):
            dispatch.fail(reason_code=ReasonCode.DEPENDENCY_TIMEOUT, processed_at=processed_at)

    def test_get_dispatch_decision_for_published(self) -> None:
        dispatch = SignalDispatch(
            identifier="01JNABCDEF1234567890123456",
            trace="trace-001",
        )
        dispatch.publish(
            published_event=EventType.SIGNAL_GENERATED,
            processed_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        )

        decision = dispatch.get_dispatch_decision()
        assert decision == DispatchDecision(
            dispatch_status=DispatchStatus.PUBLISHED,
            published_event=EventType.SIGNAL_GENERATED,
        )
