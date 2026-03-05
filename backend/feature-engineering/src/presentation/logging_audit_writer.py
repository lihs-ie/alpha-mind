"""Logging-based implementation of FeatureAuditWriter.

Writes structured audit log entries via Python logging.
In production this feeds into Cloud Logging for audit trail.
"""

from __future__ import annotations

import datetime
import logging

from domain.value_object.enums import ReasonCode
from usecase.feature_audit_writer import FeatureAuditWriter

logger = logging.getLogger("feature-engineering.audit")

SERVICE_NAME = "feature-engineering"


class LoggingFeatureAuditWriter(FeatureAuditWriter):
    """Writes feature generation audit entries as structured log messages using extra fields."""

    def write_success(
        self,
        identifier: str,
        trace: str,
        target_date: datetime.date,
        feature_version: str,
    ) -> None:
        logger.info(
            "feature_generation_success",
            extra={
                "service": SERVICE_NAME,
                "identifier": identifier,
                "trace": trace,
                "eventType": "features.generated",
                "audit_type": "feature_generation_success",
                "target_date": target_date.isoformat(),
                "feature_version": feature_version,
            },
        )

    def write_failure(
        self,
        identifier: str,
        trace: str,
        reason_code: ReasonCode,
        detail: str | None,
    ) -> None:
        logger.warning(
            "feature_generation_failure",
            extra={
                "service": SERVICE_NAME,
                "identifier": identifier,
                "trace": trace,
                "eventType": "features.generation.failed",
                "reasonCode": reason_code.value,
                "audit_type": "feature_generation_failure",
                "detail": detail,
            },
        )

    def write_duplicate(self, identifier: str, trace: str) -> None:
        logger.info(
            "feature_generation_duplicate",
            extra={
                "service": SERVICE_NAME,
                "identifier": identifier,
                "trace": trace,
                "eventType": "market.collected",
                "audit_type": "feature_generation_duplicate",
            },
        )
