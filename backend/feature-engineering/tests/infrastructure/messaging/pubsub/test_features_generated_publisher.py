"""Tests for FeaturesGeneratedPublisher."""

import datetime
import json
from unittest.mock import MagicMock

from domain.event.domain_events import FeatureGenerationCompleted
from infrastructure.messaging.pubsub.features_generated_publisher import (
    FeaturesGeneratedPublisher,
)

VALID_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
VALID_TRACE = "01ARZ3NDEKTSV4RRFFQ69G5FAW"


class TestFeaturesGeneratedPublisher:
    def test_publish_sends_cloud_events_envelope(self) -> None:
        mock_publisher_client = MagicMock()
        mock_future = MagicMock()
        mock_publisher_client.publish.return_value = mock_future

        publisher = FeaturesGeneratedPublisher(
            client=mock_publisher_client,
            topic_path="projects/alpha-mind/topics/features.generated",
        )

        event = FeatureGenerationCompleted(
            identifier=VALID_ULID,
            target_date=datetime.date(2026, 1, 15),
            feature_version="v20260115-001",
            storage_path="gs://feature_store/v20260115-001/features.parquet",
            trace=VALID_TRACE,
            occurred_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        )

        publisher.publish(event)

        mock_publisher_client.publish.assert_called_once()
        call_args = mock_publisher_client.publish.call_args

        assert call_args[0][0] == "projects/alpha-mind/topics/features.generated"

        published_data = json.loads(call_args[1]["data"])
        assert published_data["identifier"] == VALID_ULID
        assert published_data["eventType"] == "features.generated"
        assert published_data["trace"] == VALID_TRACE
        assert published_data["schemaVersion"] == "1.0.0"
        assert published_data["payload"]["targetDate"] == "2026-01-15"
        assert published_data["payload"]["featureVersion"] == "v20260115-001"

        # Verify future.result() is called to ensure delivery
        mock_future.result.assert_called_once()

    def test_publish_passes_correct_content_type(self) -> None:
        mock_publisher_client = MagicMock()
        mock_future = MagicMock()
        mock_publisher_client.publish.return_value = mock_future

        publisher = FeaturesGeneratedPublisher(
            client=mock_publisher_client,
            topic_path="projects/alpha-mind/topics/features.generated",
        )

        event = FeatureGenerationCompleted(
            identifier=VALID_ULID,
            target_date=datetime.date(2026, 1, 15),
            feature_version="v20260115-001",
            storage_path="gs://feature_store/v20260115-001/features.parquet",
            trace=VALID_TRACE,
            occurred_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        )

        publisher.publish(event)

        call_kwargs = mock_publisher_client.publish.call_args[1]
        assert call_kwargs["content_type"] == "application/json"
