"""Tests for FirestoreIdempotencyKeyRepository."""

import datetime
from unittest.mock import MagicMock

from google.api_core.exceptions import AlreadyExists

from signal_generator.domain.repositories.idempotency_key_repository import (
    IdempotencyKeyRepository,
)
from signal_generator.infrastructure.firestore.firestore_idempotency_key_repository import (
    FirestoreIdempotencyKeyRepository,
)


class TestFirestoreIdempotencyKeyRepository:
    """FirestoreIdempotencyKeyRepository のテスト。"""

    def test_implements_abstract_interface(self) -> None:
        mock_client = MagicMock()
        repository = FirestoreIdempotencyKeyRepository(firestore_client=mock_client)
        assert isinstance(repository, IdempotencyKeyRepository)

    def test_find_returns_true_when_document_exists(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        mock_document_reference.get.return_value = mock_document_snapshot
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreIdempotencyKeyRepository(firestore_client=mock_client)
        result = repository.find("01JTEST0000000000000000000")

        assert result is True
        mock_client.collection.assert_called_once_with("idempotency_keys")
        mock_client.collection.return_value.document.assert_called_once_with("01JTEST0000000000000000000")

    def test_find_returns_false_when_document_does_not_exist(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = False
        mock_document_reference.get.return_value = mock_document_snapshot
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreIdempotencyKeyRepository(firestore_client=mock_client)
        result = repository.find("01JTEST0000000000000000000")

        assert result is False

    def test_persist_returns_true_on_new_entry(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreIdempotencyKeyRepository(firestore_client=mock_client)
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        result = repository.persist("01JTEST0000000000000000000", processed_at, trace="01JTRACE000000000000000000")

        assert result is True

    def test_persist_creates_document_with_correct_fields(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreIdempotencyKeyRepository(firestore_client=mock_client)
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        repository.persist("01JTEST0000000000000000000", processed_at, trace="01JTRACE000000000000000000")

        mock_client.collection.assert_called_once_with("idempotency_keys")
        mock_client.collection.return_value.document.assert_called_once_with("01JTEST0000000000000000000")

        call_args = mock_document_reference.create.call_args
        document_data = call_args[0][0]

        assert document_data["identifier"] == "01JTEST0000000000000000000"
        assert document_data["service"] == "signal-generator"
        assert document_data["processedAt"] == processed_at
        assert document_data["trace"] == "01JTRACE000000000000000000"

    def test_persist_sets_expires_at_with_30_day_ttl(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreIdempotencyKeyRepository(firestore_client=mock_client)
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        repository.persist("01JTEST0000000000000000000", processed_at, trace="01JTRACE000000000000000000")

        call_args = mock_document_reference.create.call_args
        document_data = call_args[0][0]
        expected_expires_at = processed_at + datetime.timedelta(days=30)

        assert document_data["expiresAt"] == expected_expires_at

    def test_terminate_deletes_document(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreIdempotencyKeyRepository(firestore_client=mock_client)
        repository.terminate("01JTEST0000000000000000000")

        mock_client.collection.assert_called_once_with("idempotency_keys")
        mock_client.collection.return_value.document.assert_called_once_with("01JTEST0000000000000000000")
        mock_document_reference.delete.assert_called_once()

    def test_persist_returns_false_when_identifier_already_exists(self) -> None:
        """同一 identifier の二重処理は False を返し、副作用なく成功扱いにする。"""
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_document_reference.create.side_effect = AlreadyExists("Document already exists")
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreIdempotencyKeyRepository(firestore_client=mock_client)
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)

        result = repository.persist("01JTEST0000000000000000000", processed_at, trace="01JTRACE000000000000000000")
        assert result is False
