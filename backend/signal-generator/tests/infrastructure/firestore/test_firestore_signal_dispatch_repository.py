"""Tests for FirestoreSignalDispatchRepository."""

import datetime
from unittest.mock import MagicMock

import pytest

from signal_generator.domain.aggregates.signal_dispatch import SignalDispatch
from signal_generator.domain.enums.dispatch_status import DispatchStatus
from signal_generator.domain.enums.event_type import EventType
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.repositories.signal_dispatch_repository import (
    SignalDispatchRepository,
)
from signal_generator.infrastructure.firestore.firestore_signal_dispatch_repository import (
    FirestoreSignalDispatchRepository,
)


class TestFirestoreSignalDispatchRepository:
    """FirestoreSignalDispatchRepository のテスト。"""

    def test_implements_abstract_interface(self) -> None:
        mock_client = MagicMock()
        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        assert isinstance(repository, SignalDispatchRepository)

    def test_find_returns_signal_dispatch_when_document_exists_pending(self) -> None:
        mock_client = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        mock_document_snapshot.to_dict.return_value = {
            "identifier": "01JTEST000000000000000000",
            "trace": "01JTRACE00000000000000000",
            "dispatchStatus": "pending",
            "publishedEvent": None,
            "reasonCode": None,
            "processedAt": None,
        }
        mock_client.collection.return_value.document.return_value.get.return_value = mock_document_snapshot

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        result = repository.find("01JTEST000000000000000000")

        assert result is not None
        assert result.identifier == "01JTEST000000000000000000"
        assert result.trace == "01JTRACE00000000000000000"
        assert result.dispatch_status == DispatchStatus.PENDING

    def test_find_returns_signal_dispatch_when_published(self) -> None:
        mock_client = MagicMock()
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        mock_document_snapshot.to_dict.return_value = {
            "identifier": "01JTEST000000000000000000",
            "trace": "01JTRACE00000000000000000",
            "dispatchStatus": "published",
            "publishedEvent": "signal.generated",
            "reasonCode": None,
            "processedAt": processed_at,
        }
        mock_client.collection.return_value.document.return_value.get.return_value = mock_document_snapshot

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        result = repository.find("01JTEST000000000000000000")

        assert result is not None
        assert result.dispatch_status == DispatchStatus.PUBLISHED
        assert result.published_event == EventType.SIGNAL_GENERATED
        assert result.processed_at == processed_at

    def test_find_returns_signal_dispatch_when_failed(self) -> None:
        mock_client = MagicMock()
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        mock_document_snapshot.to_dict.return_value = {
            "identifier": "01JTEST000000000000000000",
            "trace": "01JTRACE00000000000000000",
            "dispatchStatus": "failed",
            "publishedEvent": None,
            "reasonCode": "DEPENDENCY_TIMEOUT",
            "processedAt": processed_at,
        }
        mock_client.collection.return_value.document.return_value.get.return_value = mock_document_snapshot

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        result = repository.find("01JTEST000000000000000000")

        assert result is not None
        assert result.dispatch_status == DispatchStatus.FAILED
        assert result.reason_code == ReasonCode.DEPENDENCY_TIMEOUT
        assert result.processed_at == processed_at

    def test_find_returns_none_when_document_does_not_exist(self) -> None:
        mock_client = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = False
        mock_client.collection.return_value.document.return_value.get.return_value = mock_document_snapshot

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        result = repository.find("01JTEST_NONEXISTENT")

        assert result is None

    def test_persist_pending_dispatch(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        signal_dispatch = SignalDispatch(
            identifier="01JTEST000000000000000000",
            trace="01JTRACE00000000000000000",
        )

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        repository.persist(signal_dispatch)

        mock_client.collection.assert_called_once_with("signal_dispatches")
        call_args = mock_document_reference.set.call_args
        document_data = call_args[0][0]

        assert document_data["identifier"] == "01JTEST000000000000000000"
        assert document_data["trace"] == "01JTRACE00000000000000000"
        assert document_data["dispatchStatus"] == "pending"
        assert document_data["publishedEvent"] is None
        assert document_data["reasonCode"] is None
        assert document_data["processedAt"] is None

    def test_persist_published_dispatch(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        signal_dispatch = SignalDispatch(
            identifier="01JTEST000000000000000000",
            trace="01JTRACE00000000000000000",
        )
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        signal_dispatch.publish(EventType.SIGNAL_GENERATED, processed_at)

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        repository.persist(signal_dispatch)

        call_args = mock_document_reference.set.call_args
        document_data = call_args[0][0]

        assert document_data["dispatchStatus"] == "published"
        assert document_data["publishedEvent"] == "signal.generated"
        assert document_data["processedAt"] == processed_at

    def test_persist_failed_dispatch(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        signal_dispatch = SignalDispatch(
            identifier="01JTEST000000000000000000",
            trace="01JTRACE00000000000000000",
        )
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        signal_dispatch.fail(ReasonCode.DEPENDENCY_TIMEOUT, processed_at)

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        repository.persist(signal_dispatch)

        call_args = mock_document_reference.set.call_args
        document_data = call_args[0][0]

        assert document_data["dispatchStatus"] == "failed"
        assert document_data["reasonCode"] == "DEPENDENCY_TIMEOUT"

    def test_terminate_deletes_document(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        repository.terminate("01JTEST000000000000000000")

        mock_client.collection.assert_called_once_with("signal_dispatches")
        mock_document_reference.delete.assert_called_once()

    def test_find_raises_value_error_when_document_data_is_none(self) -> None:
        mock_client = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        mock_document_snapshot.to_dict.return_value = None
        mock_client.collection.return_value.document.return_value.get.return_value = mock_document_snapshot

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)

        with pytest.raises(ValueError, match="document_data must not be None"):
            repository.find("01JTEST000000000000000000")
