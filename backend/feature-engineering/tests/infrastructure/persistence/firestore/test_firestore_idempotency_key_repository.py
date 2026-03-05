"""Tests for FirestoreIdempotencyKeyRepository."""

import datetime
from unittest.mock import MagicMock

import pytest
from google.api_core.exceptions import AlreadyExists

from infrastructure.error import InfrastructureDataFormatError
from infrastructure.persistence.firestore.firestore_idempotency_key_repository import (
    FirestoreIdempotencyKeyRepository,
)

VALID_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
SERVICE_NAME = "feature-engineering"


EXPECTED_DOCUMENT_ID = f"{SERVICE_NAME}:{VALID_ULID}"


class TestFirestoreIdempotencyKeyRepositoryReserve:
    def test_reserve_returns_true_when_newly_created(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        result = repository.reserve(VALID_ULID, "01ARZ3NDEKTSV4RRFFQ69G5FAW")

        assert result is True
        mock_collection.document.assert_called_once_with(EXPECTED_DOCUMENT_ID)
        mock_document.create.assert_called_once()
        data = mock_document.create.call_args[0][0]
        assert data["identifier"] == VALID_ULID
        assert data["service"] == SERVICE_NAME
        assert data["trace"] == "01ARZ3NDEKTSV4RRFFQ69G5FAW"
        assert data["status"] == "reserved"

    def test_reserve_returns_false_when_already_exists(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.create.side_effect = AlreadyExists("Document already exists")

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        result = repository.reserve(VALID_ULID, "01ARZ3NDEKTSV4RRFFQ69G5FAW")

        assert result is False


class TestFirestoreIdempotencyKeyRepositoryFind:
    def test_find_returns_none_when_not_found(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = False

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        result = repository.find(VALID_ULID)

        assert result is None
        mock_collection.document.assert_called_once_with(EXPECTED_DOCUMENT_ID)

    def test_find_returns_processed_at_when_exists(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = True
        processed_at = datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC)
        future_expires_at = datetime.datetime.now(datetime.UTC) + datetime.timedelta(days=30)
        mock_snapshot.to_dict.return_value = {
            "identifier": VALID_ULID,
            "service": SERVICE_NAME,
            "processedAt": processed_at,
            "trace": "01ARZ3NDEKTSV4RRFFQ69G5FAW",
            "expiresAt": future_expires_at,
        }

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        result = repository.find(VALID_ULID)

        assert result == processed_at
        mock_collection.document.assert_called_once_with(EXPECTED_DOCUMENT_ID)

    def test_find_returns_none_when_expired(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = True
        processed_at = datetime.datetime(2025, 12, 1, 9, 0, 0, tzinfo=datetime.UTC)
        past_expires_at = datetime.datetime.now(datetime.UTC) - datetime.timedelta(days=1)
        mock_snapshot.to_dict.return_value = {
            "identifier": VALID_ULID,
            "service": SERVICE_NAME,
            "processedAt": processed_at,
            "trace": "01ARZ3NDEKTSV4RRFFQ69G5FAW",
            "expiresAt": past_expires_at,
        }

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        result = repository.find(VALID_ULID)

        assert result is None
        mock_collection.document.assert_called_once_with(EXPECTED_DOCUMENT_ID)


class TestFirestoreIdempotencyKeyRepositoryPersist:
    def test_persist_stores_with_ttl_and_service_scoped_key(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        processed_at = datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC)

        trace = "01ARZ3NDEKTSV4RRFFQ69G5FAW"
        repository.persist(VALID_ULID, processed_at, trace)

        mock_client.collection.assert_called_once_with("idempotency_keys")
        mock_collection.document.assert_called_once_with(EXPECTED_DOCUMENT_ID)

        data = mock_document.set.call_args[0][0]
        assert data["identifier"] == VALID_ULID
        assert data["service"] == SERVICE_NAME
        assert data["processedAt"] == processed_at
        assert data["trace"] == trace
        # TTL: 30 days from processed_at
        expected_expires_at = processed_at + datetime.timedelta(days=30)
        assert data["expiresAt"] == expected_expires_at
        assert data["updatedAt"] == processed_at


class TestFirestoreIdempotencyKeyRepositoryTerminate:
    def test_terminate_deletes_document(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        repository.terminate(VALID_ULID)

        mock_client.collection.assert_called_once_with("idempotency_keys")
        mock_collection.document.assert_called_once_with(EXPECTED_DOCUMENT_ID)
        mock_document.delete.assert_called_once()


class TestFirestoreIdempotencyKeyRepositoryDeserializeErrors:
    def test_find_raises_for_missing_processed_at(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = {
            "identifier": VALID_ULID,
            "service": SERVICE_NAME,
            # "processedAt" is missing
        }

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        with pytest.raises(InfrastructureDataFormatError):
            repository.find(VALID_ULID)
