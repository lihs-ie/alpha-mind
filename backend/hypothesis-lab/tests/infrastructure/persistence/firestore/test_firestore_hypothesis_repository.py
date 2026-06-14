"""Tests for FirestoreHypothesisRepository."""

from __future__ import annotations

import datetime
from unittest.mock import MagicMock

import pytest

from domain.value_object.enums import HypothesisStatus, InstrumentType
from infrastructure.error import InfrastructureDataFormatError
from infrastructure.persistence.firestore.firestore_hypothesis_repository import (
    FirestoreHypothesisRepository,
)

VALID_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
VALID_TRACE = "01ARZ3NDEKTSV4RRFFQ69G5FAW"

_MINIMAL_DOC: dict[str, object] = {
    "identifier": VALID_ULID,
    "symbol": "1234",
    "instrumentType": "ETF",
    "status": "draft",
    "title": "Test Hypothesis",
    "sourceEvidence": ["source1", "source2"],
    "skillVersion": "v1.0.0",
    "instructionProfileVersion": "v1.0.0",
    "updatedAt": datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
    "insiderRisk": None,
    "requiresComplianceReview": None,
    "mnpiSelfDeclared": None,
    "autoPromotionEligible": None,
    "promotionMode": None,
    "latestFailureSummary": None,
    "trace": VALID_TRACE,
}


def _make_mock_client(snapshot_exists: bool = True, doc_data: dict[str, object] | None = None) -> MagicMock:
    mock_client = MagicMock()
    mock_collection = MagicMock()
    mock_document = MagicMock()
    mock_snapshot = MagicMock()
    mock_client.collection.return_value = mock_collection
    mock_collection.document.return_value = mock_document
    mock_document.get.return_value = mock_snapshot
    mock_snapshot.exists = snapshot_exists
    mock_snapshot.to_dict.return_value = doc_data
    return mock_client


class TestFirestoreHypothesisRepositoryFind:
    """find() should deserialize a Firestore document to a Hypothesis aggregate."""

    def test_find_returns_none_for_missing_document(self) -> None:
        mock_client = _make_mock_client(snapshot_exists=False)
        repository = FirestoreHypothesisRepository(client=mock_client)

        result = repository.find(VALID_ULID)

        assert result is None

    def test_find_returns_deserialized_hypothesis(self) -> None:
        mock_client = _make_mock_client(snapshot_exists=True, doc_data=dict(_MINIMAL_DOC))
        repository = FirestoreHypothesisRepository(client=mock_client)

        result = repository.find(VALID_ULID)

        assert result is not None
        assert result.identifier == VALID_ULID
        assert result.symbol == "1234"
        assert result.instrument_type == InstrumentType.ETF
        assert result.status == HypothesisStatus.DRAFT
        assert result.title == "Test Hypothesis"
        assert result.source_evidence == ["source1", "source2"]
        assert result.skill_version == "v1.0.0"
        assert result.instruction_profile_version == "v1.0.0"
        assert result.insider_risk is None
        assert result.promotion_mode is None
        assert result.latest_failure_summary is None

    def test_find_raises_for_invalid_status(self) -> None:
        bad_doc = dict(_MINIMAL_DOC)
        bad_doc["status"] = "nonexistent_status"
        mock_client = _make_mock_client(snapshot_exists=True, doc_data=bad_doc)
        repository = FirestoreHypothesisRepository(client=mock_client)

        with pytest.raises(InfrastructureDataFormatError):
            repository.find(VALID_ULID)

    def test_find_raises_for_missing_required_field(self) -> None:
        bad_doc = {k: v for k, v in _MINIMAL_DOC.items() if k != "symbol"}
        mock_client = _make_mock_client(snapshot_exists=True, doc_data=bad_doc)
        repository = FirestoreHypothesisRepository(client=mock_client)

        with pytest.raises(InfrastructureDataFormatError):
            repository.find(VALID_ULID)


class TestFirestoreHypothesisRepositoryFindByStatus:
    """find_by_status() should filter hypotheses by status field."""

    def test_find_by_status_filters_correctly(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_query = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.where.return_value = mock_query

        mock_doc = MagicMock()
        mock_doc.to_dict.return_value = dict(_MINIMAL_DOC)
        mock_query.stream.return_value = [mock_doc]

        repository = FirestoreHypothesisRepository(client=mock_client)
        results = repository.find_by_status(HypothesisStatus.DRAFT)

        assert len(results) == 1
        assert results[0].status == HypothesisStatus.DRAFT
        mock_collection.where.assert_called_once()

    def test_find_by_status_returns_empty_list_when_no_matches(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_query = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.where.return_value = mock_query
        mock_query.stream.return_value = []

        repository = FirestoreHypothesisRepository(client=mock_client)
        results = repository.find_by_status(HypothesisStatus.LIVE)

        assert results == []


class TestFirestoreHypothesisRepositoryPersist:
    """persist() should serialize Hypothesis to a Firestore document."""

    def test_persist_stores_hypothesis(self) -> None:
        from domain.model.hypothesis import Hypothesis

        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        hypothesis = Hypothesis(
            identifier=VALID_ULID,
            symbol="1234",
            instrument_type=InstrumentType.ETF,
            status=HypothesisStatus.DRAFT,
            title="Test Hypothesis",
            source_evidence=["source1"],
            skill_version="v1.0.0",
            instruction_profile_version="v1.0.0",
            updated_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        )

        repository = FirestoreHypothesisRepository(client=mock_client)
        repository.persist(hypothesis)

        mock_client.collection.assert_called_once_with("hypothesis_registry")
        mock_collection.document.assert_called_once_with(VALID_ULID)
        mock_document.set.assert_called_once()

        persisted_data = mock_document.set.call_args[0][0]
        assert persisted_data["identifier"] == VALID_ULID
        assert persisted_data["symbol"] == "1234"
        assert persisted_data["instrumentType"] == "ETF"
        assert persisted_data["status"] == "draft"
        assert persisted_data["title"] == "Test Hypothesis"
        assert persisted_data["sourceEvidence"] == ["source1"]
        assert persisted_data["skillVersion"] == "v1.0.0"
        assert persisted_data["instructionProfileVersion"] == "v1.0.0"
        assert persisted_data["insiderRisk"] is None
        assert persisted_data["requiresComplianceReview"] is None
        assert persisted_data["mnpiSelfDeclared"] is None
        assert persisted_data["autoPromotionEligible"] is None
        assert persisted_data["promotionMode"] is None
        assert persisted_data["latestFailureSummary"] is None


class TestFirestoreHypothesisRepositoryTerminate:
    """terminate() should delete the document from Firestore."""

    def test_terminate_deletes_document(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        repository = FirestoreHypothesisRepository(client=mock_client)
        repository.terminate(VALID_ULID)

        mock_client.collection.assert_called_once_with("hypothesis_registry")
        mock_collection.document.assert_called_once_with(VALID_ULID)
        mock_document.delete.assert_called_once()
