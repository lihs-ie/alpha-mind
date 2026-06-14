"""Tests for HypothesisBacktestedPublisher."""

from __future__ import annotations

import datetime
import json
from unittest.mock import MagicMock

import pytest

from domain.event.domain_events import HypothesisBacktested
from infrastructure.messaging.pubsub.hypothesis_backtested_publisher import (
    HypothesisBacktestedPublisher,
)

VALID_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
VALID_TRACE = "01ARZ3NDEKTSV4RRFFQ69G5FAW"
TOPIC_PATH = "projects/alpha-mind/topics/hypothesis.backtested"


def _make_event() -> HypothesisBacktested:
    return HypothesisBacktested(
        identifier=VALID_ULID,
        passed=True,
        cost_adjusted_return=0.05,
        dsr=1.2,
        pbo=0.3,
        trace=VALID_TRACE,
        occurred_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
    )


class TestHypothesisBacktestedPublisher:
    def test_publish_calls_pubsub_with_correct_data(self) -> None:
        mock_publisher_client = MagicMock()
        mock_future = MagicMock()
        mock_publisher_client.publish.return_value = mock_future

        publisher = HypothesisBacktestedPublisher(
            client=mock_publisher_client,
            topic_path=TOPIC_PATH,
        )

        publisher.publish(_make_event())

        mock_publisher_client.publish.assert_called_once()
        call_args = mock_publisher_client.publish.call_args

        assert call_args[0][0] == TOPIC_PATH

        published_data = json.loads(call_args[1]["data"])
        assert published_data["identifier"] == VALID_ULID
        assert published_data["eventType"] == "hypothesis.backtested"
        assert published_data["trace"] == VALID_TRACE
        assert published_data["schemaVersion"] == "1.0.0"
        assert published_data["payload"]["passed"] is True
        assert published_data["payload"]["costAdjustedReturn"] == 0.05
        assert published_data["payload"]["dsr"] == 1.2
        assert published_data["payload"]["pbo"] == 0.3

        mock_future.result.assert_called_once()

    def test_publish_passes_cloud_events_attributes(self) -> None:
        mock_publisher_client = MagicMock()
        mock_future = MagicMock()
        mock_publisher_client.publish.return_value = mock_future

        publisher = HypothesisBacktestedPublisher(
            client=mock_publisher_client,
            topic_path=TOPIC_PATH,
        )

        publisher.publish(_make_event())

        call_kwargs = mock_publisher_client.publish.call_args[1]
        assert call_kwargs["datacontenttype"] == "application/json"
        assert call_kwargs["ce-specversion"] == "1.0"
        assert call_kwargs["ce-id"] == VALID_ULID
        assert call_kwargs["ce-type"] == "hypothesis.backtested"
        assert call_kwargs["ce-source"] == "urn:alpha-mind:service:hypothesis-lab"
        assert call_kwargs["ce-time"] == "2026-01-15T09:00:00Z"

    def test_publish_raises_when_delivery_fails(self) -> None:
        mock_publisher_client = MagicMock()
        mock_future = MagicMock()
        mock_future.result.side_effect = Exception("Pub/Sub delivery failed")
        mock_publisher_client.publish.return_value = mock_future

        publisher = HypothesisBacktestedPublisher(
            client=mock_publisher_client,
            topic_path=TOPIC_PATH,
        )

        with pytest.raises(Exception, match="Pub/Sub delivery failed"):
            publisher.publish(_make_event())
