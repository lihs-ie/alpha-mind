"""Tests for PubSubEventPublisher composite implementation."""

from __future__ import annotations

import datetime
from unittest.mock import MagicMock

import pytest

from domain.event.domain_events import FeatureGenerationCompleted, FeatureGenerationFailed
from domain.value_object.enums import ReasonCode
from infrastructure.messaging.pubsub.pubsub_event_publisher import PubSubEventPublisher


class TestPubSubEventPublisher:
    """Tests for PubSubEventPublisher composite."""

    @staticmethod
    def _make_completed_event() -> FeatureGenerationCompleted:
        return FeatureGenerationCompleted(
            identifier="01JQXK5V6R3YBNM7GTWP0HS4EA",
            target_date=datetime.date(2026, 3, 5),
            feature_version="v-20260305-001",
            storage_path="gs://bucket/features/v-20260305-001/features.parquet",
            trace="01JQXK5V6R3YBNM7GTWP0HS4EB",
            occurred_at=datetime.datetime(2026, 3, 5, 9, 0, 0, tzinfo=datetime.UTC),
        )

    @staticmethod
    def _make_failed_event() -> FeatureGenerationFailed:
        return FeatureGenerationFailed(
            identifier="01JQXK5V6R3YBNM7GTWP0HS4EA",
            reason_code=ReasonCode.FEATURE_GENERATION_FAILED,
            detail="Something went wrong",
            trace="01JQXK5V6R3YBNM7GTWP0HS4EB",
            occurred_at=datetime.datetime(2026, 3, 5, 9, 0, 0, tzinfo=datetime.UTC),
        )

    def test_publish_features_generated_delegates_to_generated_publisher(self) -> None:
        generated_publisher = MagicMock()
        failed_publisher = MagicMock()
        publisher = PubSubEventPublisher(
            features_generated_publisher=generated_publisher,
            features_generation_failed_publisher=failed_publisher,
        )

        event = self._make_completed_event()
        publisher.publish_features_generated(event)

        generated_publisher.publish.assert_called_once_with(event)
        failed_publisher.publish.assert_not_called()

    def test_publish_features_generation_failed_delegates_to_failed_publisher(self) -> None:
        generated_publisher = MagicMock()
        failed_publisher = MagicMock()
        publisher = PubSubEventPublisher(
            features_generated_publisher=generated_publisher,
            features_generation_failed_publisher=failed_publisher,
        )

        event = self._make_failed_event()
        publisher.publish_features_generation_failed(event)

        failed_publisher.publish.assert_called_once_with(event)
        generated_publisher.publish.assert_not_called()

    def test_publish_features_generated_returns_message_id_from_publisher(self) -> None:
        generated_publisher = MagicMock()
        generated_publisher.publish.return_value = "msg-id-123"
        failed_publisher = MagicMock()
        publisher = PubSubEventPublisher(
            features_generated_publisher=generated_publisher,
            features_generation_failed_publisher=failed_publisher,
        )

        event = self._make_completed_event()
        result = publisher.publish_features_generated(event)

        assert result == "msg-id-123"

    def test_publish_features_generation_failed_returns_message_id_from_publisher(self) -> None:
        generated_publisher = MagicMock()
        failed_publisher = MagicMock()
        failed_publisher.publish.return_value = "msg-id-456"
        publisher = PubSubEventPublisher(
            features_generated_publisher=generated_publisher,
            features_generation_failed_publisher=failed_publisher,
        )

        event = self._make_failed_event()
        result = publisher.publish_features_generation_failed(event)

        assert result == "msg-id-456"

    def test_publish_features_generated_propagates_publisher_error(self) -> None:
        generated_publisher = MagicMock()
        generated_publisher.publish.side_effect = RuntimeError("publish failed")
        failed_publisher = MagicMock()
        publisher = PubSubEventPublisher(
            features_generated_publisher=generated_publisher,
            features_generation_failed_publisher=failed_publisher,
        )

        event = self._make_completed_event()
        with pytest.raises(RuntimeError, match="publish failed"):
            publisher.publish_features_generated(event)

    def test_publish_features_generation_failed_propagates_publisher_error(self) -> None:
        generated_publisher = MagicMock()
        failed_publisher = MagicMock()
        failed_publisher.publish.side_effect = RuntimeError("publish failed")
        publisher = PubSubEventPublisher(
            features_generated_publisher=generated_publisher,
            features_generation_failed_publisher=failed_publisher,
        )

        event = self._make_failed_event()
        with pytest.raises(RuntimeError, match="publish failed"):
            publisher.publish_features_generation_failed(event)
