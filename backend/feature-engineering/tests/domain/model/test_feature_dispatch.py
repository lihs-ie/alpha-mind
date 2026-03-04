"""Tests for FeatureDispatch aggregate root."""

import datetime

import pytest
from src.domain.model.feature_dispatch import FeatureDispatch, InvalidDispatchTransitionError
from src.domain.value_object.enums import DispatchStatus, PublishedEventType, ReasonCode


def _make_pending_dispatch() -> FeatureDispatch:
    """Helper to create a pending FeatureDispatch for testing."""
    return FeatureDispatch(
        identifier="01JNPQRS0000000000000001",
        dispatch_status=DispatchStatus.PENDING,
        trace="trace-abc-123",
    )


class TestFeatureDispatchCreation:
    def test_initial_state_is_pending(self) -> None:
        dispatch = _make_pending_dispatch()
        assert dispatch.dispatch_status == DispatchStatus.PENDING

    def test_identifier_is_set(self) -> None:
        dispatch = _make_pending_dispatch()
        assert dispatch.identifier == "01JNPQRS0000000000000001"

    def test_published_event_is_none_initially(self) -> None:
        dispatch = _make_pending_dispatch()
        assert dispatch.published_event is None

    def test_reason_code_is_none_initially(self) -> None:
        dispatch = _make_pending_dispatch()
        assert dispatch.reason_code is None

    def test_rejects_empty_identifier(self) -> None:
        with pytest.raises(ValueError, match="identifier must not be empty"):
            FeatureDispatch(
                identifier="",
                dispatch_status=DispatchStatus.PENDING,
                trace="trace-abc-123",
            )

    def test_rejects_empty_trace(self) -> None:
        with pytest.raises(ValueError, match="trace must not be empty"):
            FeatureDispatch(
                identifier="01JNPQRS0000000000000001",
                dispatch_status=DispatchStatus.PENDING,
                trace="",
            )

    def test_rejects_failed_without_reason_code(self) -> None:
        with pytest.raises(ValueError, match="failed dispatch status requires reason_code"):
            FeatureDispatch(
                identifier="01JNPQRS0000000000000001",
                dispatch_status=DispatchStatus.FAILED,
                trace="trace-abc-123",
                reason_code=None,
            )

    def test_rejects_published_without_published_event(self) -> None:
        with pytest.raises(ValueError, match="published dispatch status requires published_event"):
            FeatureDispatch(
                identifier="01JNPQRS0000000000000001",
                dispatch_status=DispatchStatus.PUBLISHED,
                trace="trace-abc-123",
                published_event=None,
            )


class TestFeatureDispatchPublishTransition:
    def test_transition_to_published(self) -> None:
        dispatch = _make_pending_dispatch()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)

        dispatch.publish(
            published_event=PublishedEventType.FEATURES_GENERATED,
            processed_at=processed_at,
        )

        assert dispatch.dispatch_status == DispatchStatus.PUBLISHED
        assert dispatch.published_event == PublishedEventType.FEATURES_GENERATED
        assert dispatch.processed_at == processed_at

    def test_publish_with_failed_event_type(self) -> None:
        dispatch = _make_pending_dispatch()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)

        dispatch.publish(
            published_event=PublishedEventType.FEATURES_GENERATION_FAILED,
            processed_at=processed_at,
        )

        assert dispatch.published_event == PublishedEventType.FEATURES_GENERATION_FAILED

    def test_inv_fe_004_cannot_publish_twice(self) -> None:
        """INV-FE-004: same event identifier can only transition to published once."""
        dispatch = _make_pending_dispatch()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        dispatch.publish(published_event=PublishedEventType.FEATURES_GENERATED, processed_at=processed_at)

        with pytest.raises(InvalidDispatchTransitionError):
            dispatch.publish(published_event=PublishedEventType.FEATURES_GENERATED, processed_at=processed_at)

    def test_cannot_publish_from_failed(self) -> None:
        dispatch = _make_pending_dispatch()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        dispatch.fail(reason_code=ReasonCode.DISPATCH_FAILED, processed_at=processed_at)

        with pytest.raises(InvalidDispatchTransitionError):
            dispatch.publish(published_event=PublishedEventType.FEATURES_GENERATED, processed_at=processed_at)


class TestFeatureDispatchFailTransition:
    def test_transition_to_failed(self) -> None:
        dispatch = _make_pending_dispatch()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)

        dispatch.fail(reason_code=ReasonCode.DISPATCH_FAILED, processed_at=processed_at)

        assert dispatch.dispatch_status == DispatchStatus.FAILED
        assert dispatch.reason_code == ReasonCode.DISPATCH_FAILED
        assert dispatch.processed_at == processed_at

    def test_cannot_fail_from_published(self) -> None:
        dispatch = _make_pending_dispatch()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        dispatch.publish(published_event=PublishedEventType.FEATURES_GENERATED, processed_at=processed_at)

        with pytest.raises(InvalidDispatchTransitionError):
            dispatch.fail(reason_code=ReasonCode.DISPATCH_FAILED, processed_at=processed_at)

    def test_cannot_fail_from_failed(self) -> None:
        dispatch = _make_pending_dispatch()
        processed_at = datetime.datetime(2026, 3, 3, 12, 5, 0, tzinfo=datetime.UTC)
        dispatch.fail(reason_code=ReasonCode.DISPATCH_FAILED, processed_at=processed_at)

        with pytest.raises(InvalidDispatchTransitionError):
            dispatch.fail(reason_code=ReasonCode.STATE_CONFLICT, processed_at=processed_at)


class TestFeatureDispatchImmutability:
    def test_identifier_immutable(self) -> None:
        dispatch = _make_pending_dispatch()
        with pytest.raises(AttributeError):
            dispatch.identifier = "changed"  # type: ignore[misc]
