"""Tests for FirestoreIdempotencyKeyRepository."""

import datetime
from unittest.mock import MagicMock

import pytest
from google.api_core.exceptions import AlreadyExists

from domain.repository.idempotency_key_repository import ReservationStatus
from infrastructure.error import InfrastructureDataFormatError
from infrastructure.persistence.firestore.firestore_idempotency_key_repository import (
    FirestoreIdempotencyKeyRepository,
)

VALID_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
SERVICE_NAME = "feature-engineering"
EXPECTED_DOCUMENT_ID = f"{SERVICE_NAME}:{VALID_ULID}"


class TestFirestoreIdempotencyKeyRepositoryFind:
    def test_find_returns_none_when_not_found(self) -> None:
        mock_client = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_snapshot.exists = False
        mock_document.get.return_value = mock_snapshot
        mock_client.collection.return_value.document.return_value = mock_document

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)

        assert repository.find(VALID_ULID) is None
        mock_client.collection.return_value.document.assert_called_once_with(EXPECTED_DOCUMENT_ID)

    def test_find_returns_processed_at_when_exists(self) -> None:
        mock_client = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = {
            "processedAt": processed_at,
            "expiresAt": processed_at + datetime.timedelta(days=1),
        }
        mock_document.get.return_value = mock_snapshot
        mock_client.collection.return_value.document.return_value = mock_document

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)

        assert repository.find(VALID_ULID) == processed_at

    def test_find_raises_for_invalid_processed_at(self) -> None:
        mock_client = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = {"processedAt": "invalid"}
        mock_document.get.return_value = mock_snapshot
        mock_client.collection.return_value.document.return_value = mock_document

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)

        with pytest.raises(InfrastructureDataFormatError):
            repository.find(VALID_ULID)


class TestFirestoreIdempotencyKeyRepositoryReserve:
    def test_reserve_creates_new_lease_document(self) -> None:
        mock_client = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document
        mock_document.create.return_value = None
        leased_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        lease_expires_at = leased_at + datetime.timedelta(minutes=5)

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        result = repository.reserve(VALID_ULID, leased_at, lease_expires_at, "01ARZ3NDEKTSV4RRFFQ69G5FAW")

        assert result == ReservationStatus.ACQUIRED
        data = mock_document.create.call_args[0][0]
        assert data["processedAt"] is None
        assert data["leaseExpiresAt"] == lease_expires_at
        assert data["expiresAt"] == leased_at + datetime.timedelta(days=30)

    def test_reserve_returns_processed_when_processed_at_exists(self) -> None:
        mock_client = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        processed_at = datetime.datetime(2026, 3, 5, 9, 0, 0, tzinfo=datetime.UTC)
        leased_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        lease_expires_at = leased_at + datetime.timedelta(minutes=5)
        mock_document.create.side_effect = AlreadyExists("already exists")
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = {
            "processedAt": processed_at,
            "expiresAt": leased_at + datetime.timedelta(days=1),
        }
        mock_document.get.return_value = mock_snapshot
        mock_client.collection.return_value.document.return_value = mock_document

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        result = repository.reserve(VALID_ULID, leased_at, lease_expires_at, "01ARZ3NDEKTSV4RRFFQ69G5FAW")

        assert result == ReservationStatus.PROCESSED
        mock_document.set.assert_not_called()

    def test_reserve_returns_leased_when_active_lease_exists(self) -> None:
        mock_client = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        leased_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        lease_expires_at = leased_at + datetime.timedelta(minutes=5)
        mock_document.create.side_effect = AlreadyExists("already exists")
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = {
            "processedAt": None,
            "leaseExpiresAt": leased_at + datetime.timedelta(minutes=1),
        }
        mock_document.get.return_value = mock_snapshot
        mock_client.collection.return_value.document.return_value = mock_document

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        result = repository.reserve(VALID_ULID, leased_at, lease_expires_at, "01ARZ3NDEKTSV4RRFFQ69G5FAW")

        assert result == ReservationStatus.LEASED
        mock_document.set.assert_not_called()

    def test_reserve_reacquires_when_lease_expired(self) -> None:
        mock_client = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        leased_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        lease_expires_at = leased_at + datetime.timedelta(minutes=5)
        mock_document.create.side_effect = AlreadyExists("already exists")
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = {
            "processedAt": None,
            "leaseExpiresAt": leased_at - datetime.timedelta(seconds=1),
        }
        mock_document.get.return_value = mock_snapshot
        mock_client.collection.return_value.document.return_value = mock_document

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        result = repository.reserve(VALID_ULID, leased_at, lease_expires_at, "01ARZ3NDEKTSV4RRFFQ69G5FAW")

        assert result == ReservationStatus.ACQUIRED
        updated = mock_document.set.call_args[0][0]
        assert updated["leaseExpiresAt"] == lease_expires_at


class TestFirestoreIdempotencyKeyRepositoryPersist:
    def test_persist_marks_processed_and_clears_lease(self) -> None:
        mock_client = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        repository.persist(VALID_ULID, processed_at, "01ARZ3NDEKTSV4RRFFQ69G5FAW")

        data = mock_document.set.call_args[0][0]
        assert data["processedAt"] == processed_at
        assert data["leaseExpiresAt"] is None
        assert data["expiresAt"] == processed_at + datetime.timedelta(days=30)


class TestFirestoreIdempotencyKeyRepositoryRelease:
    def test_release_marks_lease_as_expired(self) -> None:
        mock_client = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        released_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        mock_snapshot.exists = True
        mock_document.get.return_value = mock_snapshot
        mock_client.collection.return_value.document.return_value = mock_document

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        repository.release(VALID_ULID, released_at)

        data = mock_document.set.call_args[0][0]
        assert data["leaseExpiresAt"] == released_at
        assert data["updatedAt"] == released_at

    def test_release_is_noop_when_document_missing(self) -> None:
        mock_client = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_snapshot.exists = False
        mock_document.get.return_value = mock_snapshot
        mock_client.collection.return_value.document.return_value = mock_document

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        repository.release(VALID_ULID, datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC))

        mock_document.set.assert_not_called()


class TestFirestoreIdempotencyKeyRepositoryTerminate:
    def test_terminate_deletes_document(self) -> None:
        mock_client = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document

        repository = FirestoreIdempotencyKeyRepository(client=mock_client, service_name=SERVICE_NAME)
        repository.terminate(VALID_ULID)

        mock_document.delete.assert_called_once()
