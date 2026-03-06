"""Tests for FirestoreSignalDispatchRepository."""

from __future__ import annotations

from unittest.mock import MagicMock

from signal_generator.domain.aggregates.signal_dispatch import SignalDispatch
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

    def test_find_returns_none_when_document_does_not_exist(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = False
        mock_document_reference.get.return_value = mock_document_snapshot
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        result = repository.find("01JTEST0000000000000000000")

        assert result is None
        mock_client.collection.assert_called_once_with("signal_dispatches")

    def test_persist_calls_set_with_document_data(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        dispatch = SignalDispatch(
            identifier="01JTEST0000000000000000000",
            trace="01JTRACE000000000000000000",
        )
        repository.persist(dispatch)

        mock_client.collection.assert_called_once_with("signal_dispatches")
        mock_client.collection.return_value.document.assert_called_once_with("01JTEST0000000000000000000")
        mock_document_reference.set.assert_called_once()

        document_data = mock_document_reference.set.call_args[0][0]
        assert document_data["identifier"] == "01JTEST0000000000000000000"
        assert document_data["dispatchStatus"] == "pending"
        assert document_data["trace"] == "01JTRACE000000000000000000"

    def test_terminate_deletes_document(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        repository.terminate("01JTEST0000000000000000000")

        mock_client.collection.assert_called_once_with("signal_dispatches")
        mock_document_reference.delete.assert_called_once()

    def test_find_returns_pending_dispatch(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        mock_document_snapshot.to_dict.return_value = {
            "identifier": "01JTEST0000000000000000000",
            "trace": "01JTRACE000000000000000000",
            "dispatchStatus": "pending",
            "processedAt": None,
        }
        mock_document_reference.get.return_value = mock_document_snapshot
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        result = repository.find("01JTEST0000000000000000000")

        assert result is not None
        assert result.identifier == "01JTEST0000000000000000000"

        from signal_generator.domain.enums.dispatch_status import DispatchStatus

        assert result.dispatch_status == DispatchStatus.PENDING

    def test_find_returns_published_dispatch(self) -> None:
        import datetime

        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        mock_document_snapshot.to_dict.return_value = {
            "identifier": "01JTEST0000000000000000000",
            "trace": "01JTRACE000000000000000000",
            "dispatchStatus": "published",
            "processedAt": processed_at,
            "publishedEvent": "signal.generated",
        }
        mock_document_reference.get.return_value = mock_document_snapshot
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        result = repository.find("01JTEST0000000000000000000")

        assert result is not None

        from signal_generator.domain.enums.dispatch_status import DispatchStatus

        assert result.dispatch_status == DispatchStatus.PUBLISHED

    def test_find_returns_failed_dispatch(self) -> None:
        import datetime

        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        mock_document_snapshot.to_dict.return_value = {
            "identifier": "01JTEST0000000000000000000",
            "trace": "01JTRACE000000000000000000",
            "dispatchStatus": "failed",
            "processedAt": processed_at,
            "reasonCode": "DEPENDENCY_UNAVAILABLE",
        }
        mock_document_reference.get.return_value = mock_document_snapshot
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        result = repository.find("01JTEST0000000000000000000")

        assert result is not None

        from signal_generator.domain.enums.dispatch_status import DispatchStatus

        assert result.dispatch_status == DispatchStatus.FAILED

    def test_to_signal_dispatch_none_document_data_raises_value_error(self) -> None:
        """document_data が None の場合は ValueError を送出する。"""
        import pytest

        from signal_generator.infrastructure.firestore.firestore_signal_dispatch_repository import (
            _to_signal_dispatch,
        )

        with pytest.raises(ValueError, match="document_data must not be None"):
            _to_signal_dispatch(None)

    def test_persist_failed_dispatch_includes_reason_code(self) -> None:
        import datetime

        from signal_generator.domain.enums.reason_code import ReasonCode

        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        dispatch = SignalDispatch(
            identifier="01JTEST0000000000000000000",
            trace="01JTRACE000000000000000000",
        )
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        dispatch.fail(ReasonCode.DEPENDENCY_UNAVAILABLE, processed_at)
        repository.persist(dispatch)

        document_data = mock_document_reference.set.call_args[0][0]
        assert document_data["dispatchStatus"] == "failed"
        assert document_data["reasonCode"] == "DEPENDENCY_UNAVAILABLE"

    def test_persist_published_dispatch_includes_published_event(self) -> None:
        import datetime

        from signal_generator.domain.enums.event_type import EventType

        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalDispatchRepository(firestore_client=mock_client)
        dispatch = SignalDispatch(
            identifier="01JTEST0000000000000000000",
            trace="01JTRACE000000000000000000",
        )
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        dispatch.publish(EventType.SIGNAL_GENERATED, processed_at)
        repository.persist(dispatch)

        document_data = mock_document_reference.set.call_args[0][0]
        assert document_data["dispatchStatus"] == "published"
        assert document_data["publishedEvent"] == "signal.generated"
