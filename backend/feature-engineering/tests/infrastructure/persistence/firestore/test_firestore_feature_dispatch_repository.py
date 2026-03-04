"""Tests for FirestoreFeatureDispatchRepository."""

import datetime
from unittest.mock import MagicMock

from domain.model.feature_dispatch import FeatureDispatch
from domain.value_object.dispatch_decision import DispatchDecision
from domain.value_object.enums import DispatchStatus, PublishedEventType, ReasonCode
from infrastructure.persistence.firestore.firestore_feature_dispatch_repository import (
    FirestoreFeatureDispatchRepository,
)

VALID_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
VALID_TRACE = "01ARZ3NDEKTSV4RRFFQ69G5FAW"


def _make_pending_dispatch() -> FeatureDispatch:
    return FeatureDispatch(
        identifier=VALID_ULID,
        dispatch_status=DispatchStatus.PENDING,
        trace=VALID_TRACE,
        dispatch_decision=DispatchDecision(
            dispatch_status=DispatchStatus.PENDING,
            published_event=None,
            reason_code=None,
        ),
    )


def _make_published_dispatch() -> FeatureDispatch:
    return FeatureDispatch(
        identifier=VALID_ULID,
        dispatch_status=DispatchStatus.PUBLISHED,
        trace=VALID_TRACE,
        dispatch_decision=DispatchDecision(
            dispatch_status=DispatchStatus.PUBLISHED,
            published_event=PublishedEventType.FEATURES_GENERATED,
            reason_code=None,
        ),
        processed_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
    )


def _make_failed_dispatch() -> FeatureDispatch:
    return FeatureDispatch(
        identifier=VALID_ULID,
        dispatch_status=DispatchStatus.FAILED,
        trace=VALID_TRACE,
        dispatch_decision=DispatchDecision(
            dispatch_status=DispatchStatus.FAILED,
            published_event=None,
            reason_code=ReasonCode.DISPATCH_FAILED,
        ),
        processed_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
    )


class TestFirestoreFeatureDispatchRepositoryPersist:
    def test_persist_pending_dispatch(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        repository = FirestoreFeatureDispatchRepository(client=mock_client)
        repository.persist(_make_pending_dispatch())

        mock_client.collection.assert_called_once_with("feature_dispatches")
        mock_collection.document.assert_called_once_with(VALID_ULID)

        data = mock_document.set.call_args[0][0]
        assert data["identifier"] == VALID_ULID
        assert data["dispatchStatus"] == "pending"
        assert data["trace"] == VALID_TRACE
        assert data["dispatchDecision"]["dispatchStatus"] == "pending"
        assert data["dispatchDecision"]["publishedEvent"] is None
        assert data["dispatchDecision"]["reasonCode"] is None
        assert data["processedAt"] is None

    def test_persist_published_dispatch(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        repository = FirestoreFeatureDispatchRepository(client=mock_client)
        repository.persist(_make_published_dispatch())

        data = mock_document.set.call_args[0][0]
        assert data["dispatchStatus"] == "published"
        assert data["dispatchDecision"]["publishedEvent"] == "features.generated"
        assert data["processedAt"] == datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC)

    def test_persist_failed_dispatch(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        repository = FirestoreFeatureDispatchRepository(client=mock_client)
        repository.persist(_make_failed_dispatch())

        data = mock_document.set.call_args[0][0]
        assert data["dispatchStatus"] == "failed"
        assert data["dispatchDecision"]["reasonCode"] == "DISPATCH_FAILED"


class TestFirestoreFeatureDispatchRepositoryFind:
    def test_find_returns_none_when_not_found(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = False

        repository = FirestoreFeatureDispatchRepository(client=mock_client)
        assert repository.find(VALID_ULID) is None

    def test_find_returns_published_dispatch(self) -> None:
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
            "dispatchStatus": "published",
            "trace": VALID_TRACE,
            "dispatchDecision": {
                "dispatchStatus": "published",
                "publishedEvent": "features.generated",
                "reasonCode": None,
            },
            "processedAt": datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        }

        repository = FirestoreFeatureDispatchRepository(client=mock_client)
        result = repository.find(VALID_ULID)

        assert result is not None
        assert result.identifier == VALID_ULID
        assert result.dispatch_status == DispatchStatus.PUBLISHED
        assert result.dispatch_decision.published_event == PublishedEventType.FEATURES_GENERATED
        assert result.processed_at == datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC)

    def test_find_returns_failed_dispatch(self) -> None:
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
            "dispatchStatus": "failed",
            "trace": VALID_TRACE,
            "dispatchDecision": {
                "dispatchStatus": "failed",
                "publishedEvent": None,
                "reasonCode": "DISPATCH_FAILED",
            },
            "processedAt": datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        }

        repository = FirestoreFeatureDispatchRepository(client=mock_client)
        result = repository.find(VALID_ULID)

        assert result is not None
        assert result.dispatch_status == DispatchStatus.FAILED
        assert result.reason_code == ReasonCode.DISPATCH_FAILED


class TestFirestoreFeatureDispatchRepositoryTerminate:
    def test_terminate_deletes_document(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        repository = FirestoreFeatureDispatchRepository(client=mock_client)
        repository.terminate(VALID_ULID)

        mock_client.collection.assert_called_once_with("feature_dispatches")
        mock_collection.document.assert_called_once_with(VALID_ULID)
        mock_document.delete.assert_called_once()
