"""Logging-based audit writer for hypothesis-lab service.

Writes structured audit log entries via Python logging.
In production this feeds into Cloud Logging for audit trail.
"""

from __future__ import annotations

import logging

logger = logging.getLogger("hypothesis-lab.audit")

SERVICE_NAME = "hypothesis-lab"


class LoggingHypothesisAuditWriter:
    """Writes hypothesis lifecycle audit entries as structured log messages using extra fields."""

    def write_promotion(self, identifier: str, trace: str, promotion_mode: str) -> None:
        """Write a structured audit log entry for a hypothesis promotion event."""
        logger.info(
            "hypothesis_promoted",
            extra={
                "service": SERVICE_NAME,
                "identifier": identifier,
                "trace": trace,
                "eventType": "hypothesis.promoted",
                "audit_type": "hypothesis_promoted",
                "promotion_mode": promotion_mode,
            },
        )

    def write_rejection(self, identifier: str, trace: str, reason_code: str) -> None:
        """Write a structured audit log entry for a hypothesis rejection event."""
        logger.warning(
            "hypothesis_rejected",
            extra={
                "service": SERVICE_NAME,
                "identifier": identifier,
                "trace": trace,
                "eventType": "hypothesis.rejected",
                "audit_type": "hypothesis_rejected",
                "reasonCode": reason_code,
            },
        )
