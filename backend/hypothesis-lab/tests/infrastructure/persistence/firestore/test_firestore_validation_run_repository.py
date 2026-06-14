"""Tests for FirestoreValidationRunRepository."""

from __future__ import annotations

import datetime
from unittest.mock import MagicMock

from domain.value_object.enums import RunType
from infrastructure.persistence.firestore.firestore_validation_run_repository import (
    BACKTEST_COLLECTION_NAME,
    DEMO_COLLECTION_NAME,
    FirestoreValidationRunRepository,
)

VALID_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
HYPOTHESIS_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAW"
EXECUTED_AT = datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC)


_BACKTEST_DOC: dict[str, object] = {
    "identifier": VALID_ULID,
    "hypothesis": HYPOTHESIS_ULID,
    "runType": "backtest",
    "executedAt": EXECUTED_AT,
    "metrics": {
        "costAdjustedReturn": 0.05,
        "dsr": 1.2,
        "pbo": 0.3,
    },
}

_DEMO_DOC: dict[str, object] = {
    "identifier": VALID_ULID,
    "hypothesis": HYPOTHESIS_ULID,
    "runType": "demo",
    "executedAt": EXECUTED_AT,
    "demoWindow": {
        "startedAt": datetime.datetime(2026, 1, 1, 0, 0, 0, tzinfo=datetime.UTC),
        "endedAt": datetime.datetime(2026, 2, 1, 0, 0, 0, tzinfo=datetime.UTC),
        "demoPeriodDays": 31,
    },
    "promotable": True,
}


class TestFirestoreValidationRunRepositoryPersist:
    """persist() routes to the correct collection based on run_type."""

    def test_persist_backtest_run_to_backtest_runs_collection(self) -> None:
        from domain.model.validation_run import ValidationRun
        from domain.value_object.performance_metrics import PerformanceMetrics

        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        validation_run = ValidationRun(
            identifier=VALID_ULID,
            hypothesis=HYPOTHESIS_ULID,
            run_type=RunType.BACKTEST,
            executed_at=EXECUTED_AT,
            metrics=PerformanceMetrics(cost_adjusted_return=0.05, dsr=1.2, pbo=0.3),
        )

        repository = FirestoreValidationRunRepository(client=mock_client)
        repository.persist(validation_run)

        mock_client.collection.assert_called_once_with(BACKTEST_COLLECTION_NAME)
        mock_collection.document.assert_called_once_with(VALID_ULID)
        mock_document.set.assert_called_once()

        persisted_data = mock_document.set.call_args[0][0]
        assert persisted_data["identifier"] == VALID_ULID
        assert persisted_data["hypothesis"] == HYPOTHESIS_ULID
        assert persisted_data["runType"] == "backtest"
        assert persisted_data["metrics"]["costAdjustedReturn"] == 0.05
        assert persisted_data["metrics"]["dsr"] == 1.2
        assert persisted_data["metrics"]["pbo"] == 0.3

    def test_persist_demo_run_to_demo_trade_runs_collection(self) -> None:
        from domain.model.validation_run import ValidationRun
        from domain.value_object.demo_window import DemoWindow

        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        validation_run = ValidationRun(
            identifier=VALID_ULID,
            hypothesis=HYPOTHESIS_ULID,
            run_type=RunType.DEMO,
            executed_at=EXECUTED_AT,
            demo_window=DemoWindow(
                started_at=datetime.datetime(2026, 1, 1, 0, 0, 0, tzinfo=datetime.UTC),
                ended_at=datetime.datetime(2026, 2, 1, 0, 0, 0, tzinfo=datetime.UTC),
                demo_period_days=31,
            ),
            promotable=True,
        )

        repository = FirestoreValidationRunRepository(client=mock_client)
        repository.persist(validation_run)

        mock_client.collection.assert_called_once_with(DEMO_COLLECTION_NAME)
        mock_collection.document.assert_called_once_with(VALID_ULID)
        mock_document.set.assert_called_once()

        persisted_data = mock_document.set.call_args[0][0]
        assert persisted_data["runType"] == "demo"
        assert persisted_data["promotable"] is True
        assert persisted_data["demoWindow"]["demoPeriodDays"] == 31


class TestFirestoreValidationRunRepositoryFind:
    """find() searches both collections."""

    def test_find_returns_backtest_run_from_backtest_collection(self) -> None:
        mock_client = MagicMock()

        def collection_side_effect(name: str) -> MagicMock:
            mock_collection = MagicMock()
            mock_document = MagicMock()
            mock_snapshot = MagicMock()
            mock_collection.document.return_value = mock_document
            mock_document.get.return_value = mock_snapshot
            if name == BACKTEST_COLLECTION_NAME:
                mock_snapshot.exists = True
                mock_snapshot.to_dict.return_value = dict(_BACKTEST_DOC)
            else:
                mock_snapshot.exists = False
            return mock_collection

        mock_client.collection.side_effect = collection_side_effect
        repository = FirestoreValidationRunRepository(client=mock_client)

        result = repository.find(VALID_ULID)

        assert result is not None
        assert result.identifier == VALID_ULID
        assert result.run_type == RunType.BACKTEST
        assert result.metrics is not None
        assert result.metrics.cost_adjusted_return == 0.05

    def test_find_returns_demo_run_from_demo_collection(self) -> None:
        mock_client = MagicMock()

        def collection_side_effect(name: str) -> MagicMock:
            mock_collection = MagicMock()
            mock_document = MagicMock()
            mock_snapshot = MagicMock()
            mock_collection.document.return_value = mock_document
            mock_document.get.return_value = mock_snapshot
            if name == DEMO_COLLECTION_NAME:
                mock_snapshot.exists = True
                mock_snapshot.to_dict.return_value = dict(_DEMO_DOC)
            else:
                mock_snapshot.exists = False
            return mock_collection

        mock_client.collection.side_effect = collection_side_effect
        repository = FirestoreValidationRunRepository(client=mock_client)

        result = repository.find(VALID_ULID)

        assert result is not None
        assert result.run_type == RunType.DEMO
        assert result.promotable is True

    def test_find_searches_both_collections_when_not_found(self) -> None:
        mock_client = MagicMock()

        def collection_side_effect(name: str) -> MagicMock:
            mock_collection = MagicMock()
            mock_document = MagicMock()
            mock_snapshot = MagicMock()
            mock_collection.document.return_value = mock_document
            mock_document.get.return_value = mock_snapshot
            mock_snapshot.exists = False
            return mock_collection

        mock_client.collection.side_effect = collection_side_effect
        repository = FirestoreValidationRunRepository(client=mock_client)

        result = repository.find(VALID_ULID)

        assert result is None
        # Both collections should have been queried
        assert mock_client.collection.call_count == 2

    def test_find_by_run_type_returns_backtest_runs(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_client.collection.return_value = mock_collection

        mock_doc = MagicMock()
        mock_doc.to_dict.return_value = dict(_BACKTEST_DOC)
        mock_collection.stream.return_value = [mock_doc]

        repository = FirestoreValidationRunRepository(client=mock_client)
        results = repository.find_by_run_type(RunType.BACKTEST)

        mock_client.collection.assert_called_once_with(BACKTEST_COLLECTION_NAME)
        assert len(results) == 1
        assert results[0].run_type == RunType.BACKTEST


class TestFirestoreValidationRunRepositorySearch:
    """search() returns results from both collections."""

    def test_search_returns_results_from_both_collections(self) -> None:
        mock_client = MagicMock()
        call_count = 0

        def collection_side_effect(name: str) -> MagicMock:
            nonlocal call_count
            call_count += 1
            mock_collection = MagicMock()
            if name == BACKTEST_COLLECTION_NAME:
                mock_doc = MagicMock()
                mock_doc.to_dict.return_value = dict(_BACKTEST_DOC)
                mock_collection.stream.return_value = [mock_doc]
            else:
                mock_doc = MagicMock()
                mock_doc.to_dict.return_value = dict(_DEMO_DOC)
                mock_collection.stream.return_value = [mock_doc]
            return mock_collection

        mock_client.collection.side_effect = collection_side_effect
        repository = FirestoreValidationRunRepository(client=mock_client)

        results = repository.search()

        assert len(results) == 2
        run_types = {r.run_type for r in results}
        assert RunType.BACKTEST in run_types
        assert RunType.DEMO in run_types
