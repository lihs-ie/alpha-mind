"""Application service for recording failure knowledge."""

from __future__ import annotations

import datetime

from domain.repository.failure_knowledge_repository import FailureKnowledgeRepository
from domain.value_object.enums import ReasonCode
from domain.value_object.failure_summary import FailureSummary


class FailureKnowledgeRegistrar:
    """Application service for recording hypothesis failure knowledge.

    Formats and persists FailureSummary records in the failure_knowledge collection
    so that patterns of failure can be retrospectively analysed.
    """

    def __init__(self, *, failure_knowledge_repository: FailureKnowledgeRepository) -> None:
        self._failure_knowledge_repository = failure_knowledge_repository

    def record(
        self,
        *,
        hypothesis_identifier: str,
        symbol: str,
        reason_code: ReasonCode,
        detail: str,
        occurred_at: datetime.datetime,
        trace: str,
    ) -> FailureSummary:
        """Record a failure summary in the failure_knowledge collection.

        Formats a Markdown document capturing the failure context and persists it
        via FailureKnowledgeRepository.

        Args:
            hypothesis_identifier: ULID of the failing Hypothesis.
            symbol: Financial symbol of the failing hypothesis (e.g. "1234").
            reason_code: Categorised reason for the failure.
            detail: Human-readable description of the failure.
            occurred_at: UTC timestamp when the failure occurred.
            trace: Trace ULID for correlation.

        Returns:
            The FailureSummary that was persisted.
        """
        markdown_summary = self._format_markdown(
            hypothesis_identifier=hypothesis_identifier,
            symbol=symbol,
            reason_code=reason_code,
            detail=detail,
            occurred_at=occurred_at,
            trace=trace,
        )
        failure_summary = FailureSummary(
            reason_code=reason_code,
            markdown_summary=markdown_summary,
        )
        self._failure_knowledge_repository.persist(failure_summary)
        return failure_summary

    def _format_markdown(
        self,
        *,
        hypothesis_identifier: str,
        symbol: str,
        reason_code: ReasonCode,
        detail: str,
        occurred_at: datetime.datetime,
        trace: str,
    ) -> str:
        """Format a Markdown failure summary document."""
        return (
            f"## Failure Record\n\n"
            f"- **Hypothesis**: `{hypothesis_identifier}`\n"
            f"- **Symbol**: `{symbol}`\n"
            f"- **Reason**: `{reason_code.value}`\n"
            f"- **Occurred At**: `{occurred_at.isoformat()}`\n"
            f"- **Trace**: `{trace}`\n\n"
            f"### Detail\n\n"
            f"{detail}\n"
        )
