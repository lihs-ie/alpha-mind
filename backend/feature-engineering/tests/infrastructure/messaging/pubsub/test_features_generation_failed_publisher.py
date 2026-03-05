"""Tests for FeaturesGenerationFailedPublisher."""

import datetime
import json
from unittest.mock import MagicMock

from domain.event.domain_events import FeatureGenerationFailed
from domain.value_object.enums import ReasonCode
from infrastructure.messaging.pubsub.features_generation_failed_publisher import (
    FeaturesGenerationFailedPublisher,
)

VALID_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
VALID_TRACE = "01ARZ3NDEKTSV4RRFFQ69G5FAW"


class TestFeaturesGenerationFailedPublisher:
    def test_publish_sends_cloud_events_envelope(self) -> None:
        mock_publisher_client = MagicMock()
        mock_future = MagicMock()
        mock_publisher_client.publish.return_value = mock_future

        publisher = FeaturesGenerationFailedPublisher(
            client=mock_publisher_client,
            topic_path="projects/alpha-mind/topics/features.generation.failed",
        )

        event = FeatureGenerationFailed(
            identifier=VALID_ULID,
            reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
            detail="US market data unavailable",
            trace=VALID_TRACE,
            occurred_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        )

        publisher.publish(event)

        mock_publisher_client.publish.assert_called_once()
        call_args = mock_publisher_client.publish.call_args

        assert call_args[0][0] == "projects/alpha-mind/topics/features.generation.failed"

        published_data = json.loads(call_args[1]["data"])
        assert published_data["identifier"] == VALID_ULID
        assert published_data["eventType"] == "features.generation.failed"
        assert published_data["trace"] == VALID_TRACE
        assert published_data["schemaVersion"] == "1.0.0"
        assert published_data["payload"]["reasonCode"] == "DEPENDENCY_UNAVAILABLE"
        assert published_data["payload"]["detail"] == "US market data unavailable"

        mock_future.result.assert_called_once()

    def test_publish_with_none_detail(self) -> None:
        mock_publisher_client = MagicMock()
        mock_future = MagicMock()
        mock_publisher_client.publish.return_value = mock_future

        publisher = FeaturesGenerationFailedPublisher(
            client=mock_publisher_client,
            topic_path="projects/alpha-mind/topics/features.generation.failed",
        )

        event = FeatureGenerationFailed(
            identifier=VALID_ULID,
            reason_code=ReasonCode.FEATURE_GENERATION_FAILED,
            detail=None,
            trace=VALID_TRACE,
            occurred_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        )

        publisher.publish(event)

        published_data = json.loads(mock_publisher_client.publish.call_args[1]["data"])
        assert "detail" not in published_data["payload"]

    def test_publish_passes_cloud_events_attributes(self) -> None:
        mock_publisher_client = MagicMock()
        mock_future = MagicMock()
        mock_publisher_client.publish.return_value = mock_future

        publisher = FeaturesGenerationFailedPublisher(
            client=mock_publisher_client,
            topic_path="projects/alpha-mind/topics/features.generation.failed",
        )

        event = FeatureGenerationFailed(
            identifier=VALID_ULID,
            reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
            detail="US market data unavailable",
            trace=VALID_TRACE,
            occurred_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        )

        publisher.publish(event)

        call_kwargs = mock_publisher_client.publish.call_args[1]
        assert call_kwargs["datacontenttype"] == "application/json"
        assert call_kwargs["ce-specversion"] == "1.0"
        assert call_kwargs["ce-id"] == VALID_ULID
        assert call_kwargs["ce-type"] == "features.generation.failed"
        assert call_kwargs["ce-source"] == "urn:alpha-mind:service:feature-engineering"
        assert call_kwargs["ce-time"] == "2026-01-15T09:00:00Z"

    def test_publish_raises_when_delivery_fails(self) -> None:
        import pytest

        mock_publisher_client = MagicMock()
        mock_future = MagicMock()
        mock_future.result.side_effect = Exception("Pub/Sub delivery failed")
        mock_publisher_client.publish.return_value = mock_future

        publisher = FeaturesGenerationFailedPublisher(
            client=mock_publisher_client,
            topic_path="projects/alpha-mind/topics/features.generation.failed",
        )

        event = FeatureGenerationFailed(
            identifier=VALID_ULID,
            reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
            detail="US market data unavailable",
            trace=VALID_TRACE,
            occurred_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        )

        with pytest.raises(Exception, match="Pub/Sub delivery failed"):
            publisher.publish(event)
