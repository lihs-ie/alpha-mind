"""Tests for FirestoreFailureKnowledgeRepository."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from domain.value_object.enums import ReasonCode
from domain.value_object.failure_summary import FailureSummary
from infrastructure.error import InfrastructureDataFormatError
from infrastructure.persistence.firestore.firestore_failure_knowledge_repository import (
    FirestoreFailureKnowledgeRepository,
)

VALID_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
HYPOTHESIS_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAW"
TRACE_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAX"

_FAILURE_DOC: dict[str, object] = {
    "identifier": VALID_ULID,
    "hypothesis": HYPOTHESIS_ULID,
    "reasonCode": "REQUEST_VALIDATION_FAILED",
    "markdownSummary": "## Failure\n\nBacktest did not pass.",
    "trace": TRACE_ULID,
}


class TestFirestoreFailureKnowledgeRepositoryFind:
    """find() should deserialize a Firestore document to a FailureSummary."""

    def test_find_returns_none_for_missing_document(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = False

        repository = FirestoreFailureKnowledgeRepository(client=mock_client)
        result = repository.find(VALID_ULID)

        assert result is None

    def test_find_returns_failure_summary(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = dict(_FAILURE_DOC)

        repository = FirestoreFailureKnowledgeRepository(client=mock_client)
        result = repository.find(VALID_ULID)

        assert result is not None
        assert result.reason_code == ReasonCode.REQUEST_VALIDATION_FAILED
        assert result.markdown_summary == "## Failure\n\nBacktest did not pass."

    def test_find_raises_for_invalid_reason_code(self) -> None:
        bad_doc = dict(_FAILURE_DOC)
        bad_doc["reasonCode"] = "NONEXISTENT_CODE"
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = bad_doc

        repository = FirestoreFailureKnowledgeRepository(client=mock_client)
        with pytest.raises(InfrastructureDataFormatError):
            repository.find(VALID_ULID)


class TestFirestoreFailureKnowledgeRepositoryPersist:
    """persist() should store a FailureSummary with auto-generated identifier."""

    def test_persist_stores_failure_summary(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        failure_summary = FailureSummary(
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            markdown_summary="## Failure\n\nBacktest did not pass.",
        )

        repository = FirestoreFailureKnowledgeRepository(client=mock_client)
        repository.persist(failure_summary)

        mock_client.collection.assert_called_with("failure_knowledge")
        mock_document.set.assert_called_once()

        persisted_data = mock_document.set.call_args[0][0]
        assert persisted_data["reasonCode"] == "REQUEST_VALIDATION_FAILED"
        assert persisted_data["markdownSummary"] == "## Failure\n\nBacktest did not pass."
        assert "identifier" in persisted_data

    def test_persist_with_metadata_stores_full_envelope(self) -> None:
        import datetime

        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        failure_summary = FailureSummary(
            reason_code=ReasonCode.STATE_CONFLICT,
            markdown_summary="## State Conflict\n\nHypothesis in wrong state.",
        )
        created_at = datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC)

        repository = FirestoreFailureKnowledgeRepository(client=mock_client)
        repository.persist_with_metadata(
            identifier=VALID_ULID,
            hypothesis_identifier=HYPOTHESIS_ULID,
            failure_summary=failure_summary,
            trace=TRACE_ULID,
            created_at=created_at,
        )

        mock_client.collection.assert_called_once_with("failure_knowledge")
        mock_collection.document.assert_called_once_with(VALID_ULID)
        mock_document.set.assert_called_once()

        persisted_data = mock_document.set.call_args[0][0]
        assert persisted_data["identifier"] == VALID_ULID
        assert persisted_data["hypothesis"] == HYPOTHESIS_ULID
        assert persisted_data["reasonCode"] == "STATE_CONFLICT"
        assert persisted_data["markdownSummary"] == "## State Conflict\n\nHypothesis in wrong state."
        assert persisted_data["trace"] == TRACE_ULID
        assert persisted_data["createdAt"] == created_at


class TestFirestoreFailureKnowledgeRepositoryFindByReasonCode:
    """find_by_reason_code() should filter by reasonCode field."""

    def test_find_by_reason_code_returns_matching_documents(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_query = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.where.return_value = mock_query

        mock_doc = MagicMock()
        mock_doc.to_dict.return_value = dict(_FAILURE_DOC)
        mock_query.stream.return_value = [mock_doc]

        repository = FirestoreFailureKnowledgeRepository(client=mock_client)
        results = repository.find_by_reason_code(ReasonCode.REQUEST_VALIDATION_FAILED)

        assert len(results) == 1
        assert results[0].reason_code == ReasonCode.REQUEST_VALIDATION_FAILED

    def test_find_by_reason_code_returns_empty_list_when_no_matches(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_query = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.where.return_value = mock_query
        mock_query.stream.return_value = []

        repository = FirestoreFailureKnowledgeRepository(client=mock_client)
        results = repository.find_by_reason_code(ReasonCode.COMPLIANCE_REVIEW_REQUIRED)

        assert results == []
