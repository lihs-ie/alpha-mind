"""Tests for PubSubSignalEventPublisher."""

import datetime
import json
from unittest.mock import MagicMock

from signal_generator.domain.enums.degradation_flag import DegradationFlag
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.events.signal_generation_completed_event import (
    SignalGenerationCompletedEvent,
)
from signal_generator.domain.events.signal_generation_failed_event import (
    SignalGenerationFailedEvent,
)
from signal_generator.domain.value_objects.model_diagnostics_snapshot import (
    ModelDiagnosticsSnapshot,
)
from signal_generator.infrastructure.messaging.pubsub_signal_event_publisher import (
    PubSubSignalEventPublisher,
)


class TestPubSubSignalEventPublisher:
    """PubSubSignalEventPublisher のテスト。"""

    def test_publish_signal_generated_event(self) -> None:
        mock_publisher_client = MagicMock()
        future = MagicMock()
        future.result.return_value = "message-id-123"
        mock_publisher_client.publish.return_value = future

        publisher = PubSubSignalEventPublisher(
            publisher_client=mock_publisher_client,
            project_id="my-project",
        )

        model_diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
            cost_adjusted_return=0.05,
            slippage_adjusted_sharpe=1.1,
        )
        event = SignalGenerationCompletedEvent(
            identifier="01JTEST000000000000000000",
            signal_version="sv-20260305",
            model_version="v1.0.0",
            feature_version="fv-20260305",
            storage_path="gs://bucket/signals/2026-03-05.parquet",
            model_diagnostics=model_diagnostics,
            trace="01JTRACE00000000000000000",
            occurred_at=datetime.datetime(2026, 3, 5, 10, 30, 0, tzinfo=datetime.UTC),
        )

        publisher.publish_signal_generated(event)

        mock_publisher_client.publish.assert_called_once()
        publish_call = mock_publisher_client.publish.call_args

        # topic の形式を確認
        topic_path = publish_call[0][0]
        assert topic_path == "projects/my-project/topics/event-signal-generated-v1"

        # CloudEvents エンベロープの内容を確認
        message_data = json.loads(publish_call[1]["data"])
        assert message_data["identifier"] == "01JTEST000000000000000000"
        assert message_data["eventType"] == "signal.generated"
        assert message_data["trace"] == "01JTRACE00000000000000000"
        assert message_data["schemaVersion"] == "1.0"
        assert "payload" in message_data

        payload = message_data["payload"]
        assert payload["signalVersion"] == "sv-20260305"
        assert payload["modelVersion"] == "v1.0.0"
        assert payload["featureVersion"] == "fv-20260305"
        assert payload["storagePath"] == "gs://bucket/signals/2026-03-05.parquet"
        assert payload["modelDiagnostics"]["degradationFlag"] == "normal"
        assert payload["modelDiagnostics"]["requiresComplianceReview"] is False

    def test_publish_signal_generation_failed_event(self) -> None:
        mock_publisher_client = MagicMock()
        future = MagicMock()
        future.result.return_value = "message-id-456"
        mock_publisher_client.publish.return_value = future

        publisher = PubSubSignalEventPublisher(
            publisher_client=mock_publisher_client,
            project_id="my-project",
        )

        event = SignalGenerationFailedEvent(
            identifier="01JTEST000000000000000000",
            reason_code=ReasonCode.MODEL_NOT_APPROVED,
            trace="01JTRACE00000000000000000",
            occurred_at=datetime.datetime(2026, 3, 5, 10, 30, 0, tzinfo=datetime.UTC),
            detail="Model v0.9.0 is not approved",
        )

        publisher.publish_signal_generation_failed(event)

        mock_publisher_client.publish.assert_called_once()
        publish_call = mock_publisher_client.publish.call_args

        topic_path = publish_call[0][0]
        assert topic_path == "projects/my-project/topics/event-signal-generation-failed-v1"

        message_data = json.loads(publish_call[1]["data"])
        assert message_data["identifier"] == "01JTEST000000000000000000"
        assert message_data["eventType"] == "signal.generation.failed"
        assert message_data["trace"] == "01JTRACE00000000000000000"
        assert message_data["schemaVersion"] == "1.0"

        payload = message_data["payload"]
        assert payload["reasonCode"] == "MODEL_NOT_APPROVED"
        assert payload["detail"] == "Model v0.9.0 is not approved"

    def test_publish_signal_generated_event_occurred_at_is_iso8601(self) -> None:
        mock_publisher_client = MagicMock()
        future = MagicMock()
        future.result.return_value = "message-id-789"
        mock_publisher_client.publish.return_value = future

        publisher = PubSubSignalEventPublisher(
            publisher_client=mock_publisher_client,
            project_id="my-project",
        )

        model_diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        )
        event = SignalGenerationCompletedEvent(
            identifier="01JTEST000000000000000000",
            signal_version="sv-20260305",
            model_version="v1.0.0",
            feature_version="fv-20260305",
            storage_path="gs://bucket/signals/2026-03-05.parquet",
            model_diagnostics=model_diagnostics,
            trace="01JTRACE00000000000000000",
            occurred_at=datetime.datetime(2026, 3, 5, 10, 30, 0, tzinfo=datetime.UTC),
        )

        publisher.publish_signal_generated(event)

        publish_call = mock_publisher_client.publish.call_args
        message_data = json.loads(publish_call[1]["data"])

        assert message_data["occurredAt"] == "2026-03-05T10:30:00+00:00"

    def test_publish_signal_generation_failed_without_detail(self) -> None:
        mock_publisher_client = MagicMock()
        future = MagicMock()
        future.result.return_value = "message-id-999"
        mock_publisher_client.publish.return_value = future

        publisher = PubSubSignalEventPublisher(
            publisher_client=mock_publisher_client,
            project_id="my-project",
        )

        event = SignalGenerationFailedEvent(
            identifier="01JTEST000000000000000000",
            reason_code=ReasonCode.DEPENDENCY_TIMEOUT,
            trace="01JTRACE00000000000000000",
            occurred_at=datetime.datetime(2026, 3, 5, 10, 30, 0, tzinfo=datetime.UTC),
        )

        publisher.publish_signal_generation_failed(event)

        publish_call = mock_publisher_client.publish.call_args
        message_data = json.loads(publish_call[1]["data"])
        payload = message_data["payload"]

        assert payload["reasonCode"] == "DEPENDENCY_TIMEOUT"
        assert payload["detail"] is None
