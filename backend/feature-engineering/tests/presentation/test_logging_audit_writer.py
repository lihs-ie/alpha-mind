"""Tests for LoggingFeatureAuditWriter."""

from __future__ import annotations

import datetime
import logging

from domain.value_object.enums import ReasonCode
from presentation.logging_audit_writer import LoggingFeatureAuditWriter


class TestLoggingFeatureAuditWriter:
    """Tests for LoggingFeatureAuditWriter."""

    def test_write_success_logs_with_structured_extra_fields(self, caplog: logging.LogRecord) -> None:
        writer = LoggingFeatureAuditWriter()

        with caplog.at_level(logging.INFO, logger="feature-engineering.audit"):
            writer.write_success(
                identifier="01JQXK5V6R3YBNM7GTWP0HS4EA",
                trace="01JQXK5V6R3YBNM7GTWP0HS4EB",
                target_date=datetime.date(2026, 3, 5),
                feature_version="v-20260305-001",
            )

        assert len(caplog.records) == 1
        record = caplog.records[0]
        assert record.service == "feature-engineering"  # type: ignore[attr-defined]
        assert record.identifier == "01JQXK5V6R3YBNM7GTWP0HS4EA"  # type: ignore[attr-defined]
        assert record.trace == "01JQXK5V6R3YBNM7GTWP0HS4EB"  # type: ignore[attr-defined]
        assert record.eventType == "features.generated"  # type: ignore[attr-defined]

    def test_write_failure_logs_with_structured_extra_fields(self, caplog: logging.LogRecord) -> None:
        writer = LoggingFeatureAuditWriter()

        with caplog.at_level(logging.WARNING, logger="feature-engineering.audit"):
            writer.write_failure(
                identifier="01JQXK5V6R3YBNM7GTWP0HS4EA",
                trace="01JQXK5V6R3YBNM7GTWP0HS4EB",
                reason_code=ReasonCode.FEATURE_GENERATION_FAILED,
                detail="Something went wrong",
            )

        assert len(caplog.records) == 1
        record = caplog.records[0]
        assert record.service == "feature-engineering"  # type: ignore[attr-defined]
        assert record.identifier == "01JQXK5V6R3YBNM7GTWP0HS4EA"  # type: ignore[attr-defined]
        assert record.trace == "01JQXK5V6R3YBNM7GTWP0HS4EB"  # type: ignore[attr-defined]
        assert record.reasonCode == "FEATURE_GENERATION_FAILED"  # type: ignore[attr-defined]

    def test_write_failure_with_none_detail(self) -> None:
        writer = LoggingFeatureAuditWriter()

        writer.write_failure(
            identifier="01JQXK5V6R3YBNM7GTWP0HS4EA",
            trace="01JQXK5V6R3YBNM7GTWP0HS4EB",
            reason_code=ReasonCode.DATA_QUALITY_LEAK_DETECTED,
            detail=None,
        )
        # Verify no exception raised

    def test_write_duplicate_logs_with_structured_extra_fields(self, caplog: logging.LogRecord) -> None:
        writer = LoggingFeatureAuditWriter()

        with caplog.at_level(logging.INFO, logger="feature-engineering.audit"):
            writer.write_duplicate(
                identifier="01JQXK5V6R3YBNM7GTWP0HS4EA",
                trace="01JQXK5V6R3YBNM7GTWP0HS4EB",
            )

        assert len(caplog.records) == 1
        record = caplog.records[0]
        assert record.service == "feature-engineering"  # type: ignore[attr-defined]
        assert record.identifier == "01JQXK5V6R3YBNM7GTWP0HS4EA"  # type: ignore[attr-defined]
        assert record.trace == "01JQXK5V6R3YBNM7GTWP0HS4EB"  # type: ignore[attr-defined]

    def test_is_instance_of_feature_audit_writer(self) -> None:
        from usecase.feature_audit_writer import FeatureAuditWriter

        writer = LoggingFeatureAuditWriter()
        assert isinstance(writer, FeatureAuditWriter)
