"""Tests for FirestoreModelRegistryRepository."""

import datetime
from unittest.mock import MagicMock

import pytest

from signal_generator.domain.enums.model_status import ModelStatus
from signal_generator.domain.repositories.model_registry_repository import (
    ModelRegistryRepository,
)
from signal_generator.infrastructure.firestore.firestore_model_registry_repository import (
    FirestoreModelRegistryRepository,
)


class TestFirestoreModelRegistryRepository:
    """FirestoreModelRegistryRepository のテスト。"""

    def test_implements_abstract_interface(self) -> None:
        mock_client = MagicMock()
        repository = FirestoreModelRegistryRepository(firestore_client=mock_client)
        assert isinstance(repository, ModelRegistryRepository)

    def test_find_returns_model_snapshot_when_document_exists(self) -> None:
        mock_client = MagicMock()
        approved_at = datetime.datetime(2026, 3, 1, 12, 0, 0, tzinfo=datetime.UTC)
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        mock_document_snapshot.to_dict.return_value = {
            "modelVersion": "v1.2.0",
            "status": "approved",
            "metrics": {
                "oosReturn": 0.05,
                "sharpe": 1.2,
                "maxDrawdown": 0.1,
                "turnover": 0.3,
                "pbo": 0.02,
                "dsr": 0.95,
            },
            "featureVersion": "fv-20260301",
            "createdAt": datetime.datetime(2026, 2, 28, 10, 0, 0, tzinfo=datetime.UTC),
            "decidedAt": approved_at,
            "decidedBy": "admin@example.com",
        }
        mock_client.collection.return_value.document.return_value.get.return_value = mock_document_snapshot

        repository = FirestoreModelRegistryRepository(firestore_client=mock_client)
        result = repository.find("v1.2.0")

        assert result is not None
        assert result.model_version == "v1.2.0"
        assert result.status == ModelStatus.APPROVED
        assert result.approved_at == approved_at
        mock_client.collection.assert_called_once_with("model_registry")

    def test_find_returns_none_when_document_does_not_exist(self) -> None:
        mock_client = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = False
        mock_client.collection.return_value.document.return_value.get.return_value = mock_document_snapshot

        repository = FirestoreModelRegistryRepository(firestore_client=mock_client)
        result = repository.find("v999.0.0")

        assert result is None

    def test_find_by_status_returns_model_snapshot_when_found(self) -> None:
        mock_client = MagicMock()
        approved_at = datetime.datetime(2026, 3, 1, 12, 0, 0, tzinfo=datetime.UTC)
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.to_dict.return_value = {
            "modelVersion": "v2.0.0",
            "status": "approved",
            "metrics": {},
            "featureVersion": "fv-20260301",
            "createdAt": datetime.datetime(2026, 2, 28, 10, 0, 0, tzinfo=datetime.UTC),
            "decidedAt": approved_at,
            "decidedBy": "admin@example.com",
        }

        mock_query = MagicMock()
        mock_query.limit.return_value.stream.return_value = iter([mock_document_snapshot])
        mock_client.collection.return_value.where.return_value.order_by.return_value = mock_query

        repository = FirestoreModelRegistryRepository(firestore_client=mock_client)
        result = repository.find_by_status(ModelStatus.APPROVED)

        assert result is not None
        assert result.model_version == "v2.0.0"
        assert result.status == ModelStatus.APPROVED

    def test_find_by_status_returns_none_when_not_found(self) -> None:
        mock_client = MagicMock()
        mock_query = MagicMock()
        mock_query.limit.return_value.stream.return_value = iter([])
        mock_client.collection.return_value.where.return_value.order_by.return_value = mock_query

        repository = FirestoreModelRegistryRepository(firestore_client=mock_client)
        result = repository.find_by_status(ModelStatus.APPROVED)

        assert result is None

    def test_search_returns_matching_model_snapshots(self) -> None:
        mock_client = MagicMock()
        approved_at_1 = datetime.datetime(2026, 3, 1, 12, 0, 0, tzinfo=datetime.UTC)
        approved_at_2 = datetime.datetime(2026, 3, 2, 12, 0, 0, tzinfo=datetime.UTC)

        mock_document_1 = MagicMock()
        mock_document_1.to_dict.return_value = {
            "modelVersion": "v1.0.0",
            "status": "approved",
            "metrics": {},
            "featureVersion": "fv-20260301",
            "createdAt": datetime.datetime(2026, 2, 28, 10, 0, 0, tzinfo=datetime.UTC),
            "decidedAt": approved_at_1,
            "decidedBy": "admin@example.com",
        }
        mock_document_2 = MagicMock()
        mock_document_2.to_dict.return_value = {
            "modelVersion": "v2.0.0",
            "status": "approved",
            "metrics": {},
            "featureVersion": "fv-20260302",
            "createdAt": datetime.datetime(2026, 3, 1, 10, 0, 0, tzinfo=datetime.UTC),
            "decidedAt": approved_at_2,
            "decidedBy": "admin@example.com",
        }

        mock_query = MagicMock()
        mock_query.limit.return_value.stream.return_value = iter([mock_document_1, mock_document_2])
        mock_client.collection.return_value.where.return_value = mock_query

        repository = FirestoreModelRegistryRepository(firestore_client=mock_client)
        results = repository.search({"status": "approved"})

        assert len(results) == 2
        assert results[0].model_version == "v1.0.0"
        assert results[1].model_version == "v2.0.0"

    def test_search_returns_empty_list_when_no_matches(self) -> None:
        mock_client = MagicMock()
        mock_query = MagicMock()
        mock_query.limit.return_value.stream.return_value = iter([])
        mock_client.collection.return_value.where.return_value = mock_query

        repository = FirestoreModelRegistryRepository(firestore_client=mock_client)
        results = repository.search({"status": "candidate"})

        assert results == []

    def test_find_returns_none_approved_at_for_candidate_model(self) -> None:
        mock_client = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        mock_document_snapshot.to_dict.return_value = {
            "modelVersion": "v3.0.0",
            "status": "candidate",
            "metrics": {},
            "featureVersion": "fv-20260305",
            "createdAt": datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC),
        }
        mock_client.collection.return_value.document.return_value.get.return_value = mock_document_snapshot

        repository = FirestoreModelRegistryRepository(firestore_client=mock_client)
        result = repository.find("v3.0.0")

        assert result is not None
        assert result.status == ModelStatus.CANDIDATE
        assert result.approved_at is None

    def test_find_raises_value_error_when_document_data_is_none(self) -> None:
        mock_client = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        mock_document_snapshot.to_dict.return_value = None
        mock_client.collection.return_value.document.return_value.get.return_value = mock_document_snapshot

        repository = FirestoreModelRegistryRepository(firestore_client=mock_client)

        with pytest.raises(ValueError, match="document_data must not be None"):
            repository.find("v1.0.0")
