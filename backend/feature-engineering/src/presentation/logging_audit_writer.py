"""Logging-based implementation of FeatureAuditWriter.

Writes structured audit log entries via Python logging.
In production this feeds into Cloud Logging for audit trail.
"""

from __future__ import annotations

import datetime
import json
import logging

from domain.value_object.enums import ReasonCode
from usecase.feature_audit_writer import FeatureAuditWriter

logger = logging.getLogger("feature-engineering.audit")


class LoggingFeatureAuditWriter(FeatureAuditWriter):
    """Writes feature generation audit entries as structured JSON log messages."""

    def write_success(
        self,
        identifier: str,
        trace: str,
        target_date: datetime.date,
        feature_version: str,
    ) -> None:
        logger.info(
            json.dumps({
                "audit_type": "feature_generation_success",
                "identifier": identifier,
                "trace": trace,
                "target_date": target_date.isoformat(),
                "feature_version": feature_version,
                "service": "feature-engineering",
            }),
        )

    def write_failure(
        self,
        identifier: str,
        trace: str,
        reason_code: ReasonCode,
        detail: str | None,
    ) -> None:
        logger.warning(
            json.dumps({
                "audit_type": "feature_generation_failure",
                "identifier": identifier,
                "trace": trace,
                "reason_code": reason_code.value,
                "detail": detail,
                "service": "feature-engineering",
            }),
        )

    def write_duplicate(self, identifier: str, trace: str) -> None:
        logger.info(
            json.dumps({
                "audit_type": "feature_generation_duplicate",
                "identifier": identifier,
                "trace": trace,
                "service": "feature-engineering",
            }),
        )
