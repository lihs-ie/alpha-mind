"""Schema compliance tests for event envelopes.

Verifies that published messages conform to the CloudEvents envelope
specification defined in AsyncAPI / 共通設計.
"""

import datetime
import json
from typing import Any
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

_REQUIRED_ENVELOPE_KEYS = {"identifier", "eventType", "occurredAt", "trace", "schemaVersion", "payload"}


def _publish_and_extract(event: Any, method_name: str) -> dict[str, Any]:
    """Publish an event via mock and return the parsed envelope."""
    mock_publisher_client = MagicMock()
    future = MagicMock()
    future.result.return_value = "message-id"
    mock_publisher_client.publish.return_value = future

    publisher = PubSubSignalEventPublisher(
        publisher_client=mock_publisher_client,
        project_id="test-project",
    )
    getattr(publisher, method_name)(event)

    publish_call = mock_publisher_client.publish.call_args
    return json.loads(publish_call[1]["data"])


class TestSignalGeneratedEnvelopeSchemaCompliance:
    """signal.generated エンベロープが CloudEvents 仕様に準拠していることを検証する。"""

    def _make_event(
        self,
        cost_adjusted_return: float | None = 0.05,
        slippage_adjusted_sharpe: float | None = 1.1,
    ) -> SignalGenerationCompletedEvent:
        model_diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
            cost_adjusted_return=cost_adjusted_return,
            slippage_adjusted_sharpe=slippage_adjusted_sharpe,
        )
        return SignalGenerationCompletedEvent(
            identifier="01JTEST000000000000000000",
            signal_version="sv-20260305",
            model_version="v1.0.0",
            feature_version="fv-20260305",
            storage_path="gs://bucket/signals/2026-03-05.parquet",
            model_diagnostics=model_diagnostics,
            trace="01JTRACE00000000000000000",
            occurred_at=datetime.datetime(2026, 3, 5, 10, 30, 0, tzinfo=datetime.UTC),
        )

    def test_envelope_contains_all_required_keys(self) -> None:
        envelope = _publish_and_extract(self._make_event(), "publish_signal_generated")
        assert _REQUIRED_ENVELOPE_KEYS.issubset(envelope.keys())

    def test_envelope_contains_no_extra_top_level_keys(self) -> None:
        envelope = _publish_and_extract(self._make_event(), "publish_signal_generated")
        assert set(envelope.keys()) == _REQUIRED_ENVELOPE_KEYS

    def test_schema_version_is_semver(self) -> None:
        envelope = _publish_and_extract(self._make_event(), "publish_signal_generated")
        parts = envelope["schemaVersion"].split(".")
        assert len(parts) == 3
        assert all(part.isdigit() for part in parts)

    def test_occurred_at_is_iso8601_with_timezone(self) -> None:
        envelope = _publish_and_extract(self._make_event(), "publish_signal_generated")
        parsed = datetime.datetime.fromisoformat(envelope["occurredAt"])
        assert parsed.tzinfo is not None

    def test_optional_diagnostics_fields_omitted_when_none(self) -> None:
        """None のフィールドは null ではなくキー自体が省略される。"""
        envelope = _publish_and_extract(
            self._make_event(cost_adjusted_return=None, slippage_adjusted_sharpe=None),
            "publish_signal_generated",
        )
        diagnostics = envelope["payload"]["modelDiagnostics"]
        assert "costAdjustedReturn" not in diagnostics
        assert "slippageAdjustedSharpe" not in diagnostics

    def test_optional_diagnostics_fields_present_when_set(self) -> None:
        envelope = _publish_and_extract(self._make_event(), "publish_signal_generated")
        diagnostics = envelope["payload"]["modelDiagnostics"]
        assert "costAdjustedReturn" in diagnostics
        assert "slippageAdjustedSharpe" in diagnostics

    def test_payload_contains_no_null_values(self) -> None:
        """payload 内に null 値が含まれないことを検証する。"""
        envelope = _publish_and_extract(
            self._make_event(cost_adjusted_return=None, slippage_adjusted_sharpe=None),
            "publish_signal_generated",
        )
        self._assert_no_null_values(envelope["payload"])

    def _assert_no_null_values(self, data: Any, path: str = "payload") -> None:
        if isinstance(data, dict):
            for key, value in data.items():
                current_path = f"{path}.{key}"
                assert value is not None, f"{current_path} should not be null"
                self._assert_no_null_values(value, current_path)
        elif isinstance(data, list):
            for index, item in enumerate(data):
                self._assert_no_null_values(item, f"{path}[{index}]")


class TestSignalGenerationFailedEnvelopeSchemaCompliance:
    """signal.generation.failed エンベロープが CloudEvents 仕様に準拠していることを検証する。"""

    def _make_event(self, detail: str | None = None) -> SignalGenerationFailedEvent:
        return SignalGenerationFailedEvent(
            identifier="01JTEST000000000000000000",
            reason_code=ReasonCode.MODEL_NOT_APPROVED,
            trace="01JTRACE00000000000000000",
            occurred_at=datetime.datetime(2026, 3, 5, 10, 30, 0, tzinfo=datetime.UTC),
            detail=detail,
        )

    def test_envelope_contains_all_required_keys(self) -> None:
        envelope = _publish_and_extract(self._make_event(), "publish_signal_generation_failed")
        assert _REQUIRED_ENVELOPE_KEYS.issubset(envelope.keys())

    def test_envelope_contains_no_extra_top_level_keys(self) -> None:
        envelope = _publish_and_extract(self._make_event(), "publish_signal_generation_failed")
        assert set(envelope.keys()) == _REQUIRED_ENVELOPE_KEYS

    def test_schema_version_is_semver(self) -> None:
        envelope = _publish_and_extract(self._make_event(), "publish_signal_generation_failed")
        parts = envelope["schemaVersion"].split(".")
        assert len(parts) == 3
        assert all(part.isdigit() for part in parts)

    def test_occurred_at_is_iso8601_with_timezone(self) -> None:
        envelope = _publish_and_extract(self._make_event(), "publish_signal_generation_failed")
        parsed = datetime.datetime.fromisoformat(envelope["occurredAt"])
        assert parsed.tzinfo is not None

    def test_detail_omitted_when_none(self) -> None:
        """detail が None の場合はキー自体が省略される。"""
        envelope = _publish_and_extract(self._make_event(detail=None), "publish_signal_generation_failed")
        assert "detail" not in envelope["payload"]

    def test_detail_present_when_set(self) -> None:
        envelope = _publish_and_extract(
            self._make_event(detail="Model v0.9.0 is not approved"),
            "publish_signal_generation_failed",
        )
        assert envelope["payload"]["detail"] == "Model v0.9.0 is not approved"

    def test_payload_contains_no_null_values(self) -> None:
        """payload 内に null 値が含まれないことを検証する。"""
        envelope = _publish_and_extract(self._make_event(detail=None), "publish_signal_generation_failed")
        self._assert_no_null_values(envelope["payload"])

    def _assert_no_null_values(self, data: Any, path: str = "payload") -> None:
        if isinstance(data, dict):
            for key, value in data.items():
                current_path = f"{path}.{key}"
                assert value is not None, f"{current_path} should not be null"
                self._assert_no_null_values(value, current_path)
        elif isinstance(data, list):
            for index, item in enumerate(data):
                self._assert_no_null_values(item, f"{path}[{index}]")
