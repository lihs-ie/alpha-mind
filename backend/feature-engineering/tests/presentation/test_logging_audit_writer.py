"""Tests for LoggingFeatureAuditWriter."""

from __future__ import annotations

import datetime

from domain.value_object.enums import ReasonCode
from presentation.logging_audit_writer import LoggingFeatureAuditWriter


class TestLoggingFeatureAuditWriter:
    """Tests for LoggingFeatureAuditWriter."""

    def test_write_success_logs_structured_json(self) -> None:
        writer = LoggingFeatureAuditWriter()

        writer.write_success(
            identifier="01JQXK5V6R3YBNM7GTWP0HS4EA",
            trace="01JQXK5V6R3YBNM7GTWP0HS4EB",
            target_date=datetime.date(2026, 3, 5),
            feature_version="v-20260305-001",
        )
        # Verify no exception raised - audit writer should not throw

    def test_write_failure_logs_structured_json(self) -> None:
        writer = LoggingFeatureAuditWriter()

        writer.write_failure(
            identifier="01JQXK5V6R3YBNM7GTWP0HS4EA",
            trace="01JQXK5V6R3YBNM7GTWP0HS4EB",
            reason_code=ReasonCode.FEATURE_GENERATION_FAILED,
            detail="Something went wrong",
        )
        # Verify no exception raised

    def test_write_failure_with_none_detail(self) -> None:
        writer = LoggingFeatureAuditWriter()

        writer.write_failure(
            identifier="01JQXK5V6R3YBNM7GTWP0HS4EA",
            trace="01JQXK5V6R3YBNM7GTWP0HS4EB",
            reason_code=ReasonCode.DATA_QUALITY_LEAK_DETECTED,
            detail=None,
        )
        # Verify no exception raised

    def test_write_duplicate_logs_structured_json(self) -> None:
        writer = LoggingFeatureAuditWriter()

        writer.write_duplicate(
            identifier="01JQXK5V6R3YBNM7GTWP0HS4EA",
            trace="01JQXK5V6R3YBNM7GTWP0HS4EB",
        )
        # Verify no exception raised

    def test_is_instance_of_feature_audit_writer(self) -> None:
        from usecase.feature_audit_writer import FeatureAuditWriter

        writer = LoggingFeatureAuditWriter()
        assert isinstance(writer, FeatureAuditWriter)
