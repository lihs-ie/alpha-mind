"""Tests for FailureKnowledgeRegistrar application service."""

from __future__ import annotations

import datetime
from unittest.mock import MagicMock

from application.failure_knowledge_service import FailureKnowledgeRegistrar
from domain.repository.failure_knowledge_repository import FailureKnowledgeRepository
from domain.value_object.enums import ReasonCode
from domain.value_object.failure_summary import FailureSummary

_NOW = datetime.datetime(2026, 3, 1, 12, 0, 0, tzinfo=datetime.UTC)
_TRACE = "01JNPQRS000000000000000001"


class TestFailureKnowledgeRegistrar:
    """Tests for FailureKnowledgeRegistrar.record."""

    def test_records_failure_summary(self) -> None:
        """record() persists a FailureSummary via the repository."""
        failure_knowledge_repository = MagicMock(spec=FailureKnowledgeRepository)
        registrar = FailureKnowledgeRegistrar(failure_knowledge_repository=failure_knowledge_repository)

        result = registrar.record(
            hypothesis_identifier="01JNPQRS000000000000000010",
            symbol="1234",
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            detail="Backtest did not pass DSR threshold.",
            occurred_at=_NOW,
            trace=_TRACE,
        )

        failure_knowledge_repository.persist.assert_called_once()
        persisted: FailureSummary = failure_knowledge_repository.persist.call_args[0][0]
        assert isinstance(persisted, FailureSummary)
        assert persisted.reason_code == ReasonCode.REQUEST_VALIDATION_FAILED
        assert persisted is result

    def test_markdown_summary_contains_hypothesis_identifier(self) -> None:
        """The generated Markdown summary references the hypothesis identifier."""
        failure_knowledge_repository = MagicMock(spec=FailureKnowledgeRepository)
        registrar = FailureKnowledgeRegistrar(failure_knowledge_repository=failure_knowledge_repository)

        result = registrar.record(
            hypothesis_identifier="01JNPQRS000000000000000010",
            symbol="1234",
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            detail="Some failure detail.",
            occurred_at=_NOW,
            trace=_TRACE,
        )

        assert "01JNPQRS000000000000000010" in result.markdown_summary

    def test_markdown_summary_contains_symbol(self) -> None:
        """The generated Markdown summary references the symbol."""
        failure_knowledge_repository = MagicMock(spec=FailureKnowledgeRepository)
        registrar = FailureKnowledgeRegistrar(failure_knowledge_repository=failure_knowledge_repository)

        result = registrar.record(
            hypothesis_identifier="01JNPQRS000000000000000010",
            symbol="7203",
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            detail="Some failure detail.",
            occurred_at=_NOW,
            trace=_TRACE,
        )

        assert "7203" in result.markdown_summary

    def test_markdown_summary_contains_detail(self) -> None:
        """The generated Markdown summary embeds the provided detail text."""
        failure_knowledge_repository = MagicMock(spec=FailureKnowledgeRepository)
        registrar = FailureKnowledgeRegistrar(failure_knowledge_repository=failure_knowledge_repository)

        result = registrar.record(
            hypothesis_identifier="01JNPQRS000000000000000010",
            symbol="1234",
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            detail="DSR below threshold of 0.5.",
            occurred_at=_NOW,
            trace=_TRACE,
        )

        assert "DSR below threshold of 0.5." in result.markdown_summary

    def test_markdown_summary_contains_reason_code(self) -> None:
        """The generated Markdown summary includes the reason code value."""
        failure_knowledge_repository = MagicMock(spec=FailureKnowledgeRepository)
        registrar = FailureKnowledgeRegistrar(failure_knowledge_repository=failure_knowledge_repository)

        result = registrar.record(
            hypothesis_identifier="01JNPQRS000000000000000010",
            symbol="1234",
            reason_code=ReasonCode.STATE_CONFLICT,
            detail="Unexpected state conflict.",
            occurred_at=_NOW,
            trace=_TRACE,
        )

        assert ReasonCode.STATE_CONFLICT.value in result.markdown_summary

    def test_markdown_summary_contains_trace(self) -> None:
        """The generated Markdown summary includes the trace identifier."""
        failure_knowledge_repository = MagicMock(spec=FailureKnowledgeRepository)
        registrar = FailureKnowledgeRegistrar(failure_knowledge_repository=failure_knowledge_repository)

        result = registrar.record(
            hypothesis_identifier="01JNPQRS000000000000000010",
            symbol="1234",
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            detail="Some failure detail.",
            occurred_at=_NOW,
            trace=_TRACE,
        )

        assert _TRACE in result.markdown_summary

    def test_markdown_summary_is_non_empty_string(self) -> None:
        """The generated Markdown summary is a non-empty string."""
        failure_knowledge_repository = MagicMock(spec=FailureKnowledgeRepository)
        registrar = FailureKnowledgeRegistrar(failure_knowledge_repository=failure_knowledge_repository)

        result = registrar.record(
            hypothesis_identifier="01JNPQRS000000000000000010",
            symbol="1234",
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            detail="Failure detail.",
            occurred_at=_NOW,
            trace=_TRACE,
        )

        assert isinstance(result.markdown_summary, str)
        assert len(result.markdown_summary) > 0
