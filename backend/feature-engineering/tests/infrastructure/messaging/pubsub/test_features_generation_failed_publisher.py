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
        assert published_data["payload"]["detail"] is None
