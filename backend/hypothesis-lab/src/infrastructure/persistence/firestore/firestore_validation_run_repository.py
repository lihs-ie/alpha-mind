"""Firestore implementation of ValidationRunRepository.

Routes to two separate collections:
  - backtest_runs  (runType=backtest)
  - demo_trade_runs (runType=demo)
"""

from __future__ import annotations

import datetime
from typing import Any, cast

from google.cloud.firestore_v1 import Client
from google.cloud.firestore_v1.base_document import DocumentSnapshot

from domain.model.validation_run import ValidationRun
from domain.repository.validation_run_repository import ValidationRunRepository
from domain.value_object.demo_window import DemoWindow
from domain.value_object.enums import RunType
from domain.value_object.performance_metrics import PerformanceMetrics
from infrastructure.error import InfrastructureDataFormatError

BACKTEST_COLLECTION_NAME = "backtest_runs"
DEMO_COLLECTION_NAME = "demo_trade_runs"

ValidationRunIdentifier = str


class FirestoreValidationRunRepository(ValidationRunRepository):
    """Firestore-backed repository for ValidationRun entities.

    Routes backtest runs to 'backtest_runs' and demo runs to 'demo_trade_runs'.
    """

    def __init__(self, client: Client) -> None:
        self._client = client

    def find(self, identifier: ValidationRunIdentifier) -> ValidationRun | None:
        """Search both collections for the identifier."""
        backtest_snapshot = cast(
            DocumentSnapshot,
            self._client.collection(BACKTEST_COLLECTION_NAME).document(identifier).get(),
        )
        if backtest_snapshot.exists:
            data = backtest_snapshot.to_dict()
            if data is not None:
                return _deserialize(data)

        demo_snapshot = cast(
            DocumentSnapshot,
            self._client.collection(DEMO_COLLECTION_NAME).document(identifier).get(),
        )
        if demo_snapshot.exists:
            data = demo_snapshot.to_dict()
            if data is not None:
                return _deserialize(data)

        return None

    def find_by_run_type(self, run_type: RunType) -> list[ValidationRun]:
        collection_name = _collection_for_run_type(run_type)
        collection_reference = self._client.collection(collection_name)
        return [
            _deserialize(data) for document in collection_reference.stream() if (data := document.to_dict()) is not None
        ]

    def search(self, criteria: dict[str, Any] | None = None) -> list[ValidationRun]:
        results: list[ValidationRun] = []

        backtest_collection = self._client.collection(BACKTEST_COLLECTION_NAME)
        for document in backtest_collection.stream():
            data = document.to_dict()
            if data is not None:
                results.append(_deserialize(data))

        demo_collection = self._client.collection(DEMO_COLLECTION_NAME)
        for document in demo_collection.stream():
            data = document.to_dict()
            if data is not None:
                results.append(_deserialize(data))

        return results

    def persist(self, validation_run: ValidationRun) -> None:
        collection_name = _collection_for_run_type(validation_run.run_type)
        data = _serialize(validation_run)
        self._client.collection(collection_name).document(validation_run.identifier).set(data)

    def terminate(self, identifier: ValidationRunIdentifier) -> None:
        """Delete from both collections (identifier is unique across both)."""
        self._client.collection(BACKTEST_COLLECTION_NAME).document(identifier).delete()
        self._client.collection(DEMO_COLLECTION_NAME).document(identifier).delete()


def _collection_for_run_type(run_type: RunType) -> str:
    if run_type == RunType.BACKTEST:
        return BACKTEST_COLLECTION_NAME
    return DEMO_COLLECTION_NAME


def _serialize(validation_run: ValidationRun) -> dict[str, Any]:
    """Convert ValidationRun entity to Firestore document."""
    data: dict[str, Any] = {
        "identifier": validation_run.identifier,
        "hypothesis": validation_run.hypothesis,
        "runType": validation_run.run_type.value,
        "executedAt": validation_run.executed_at,
    }

    if validation_run.run_type == RunType.BACKTEST:
        metrics_data: dict[str, Any] | None = None
        if validation_run.metrics is not None:
            metrics_data = {
                "costAdjustedReturn": validation_run.metrics.cost_adjusted_return,
                "dsr": validation_run.metrics.dsr,
                "pbo": validation_run.metrics.pbo,
            }
        data["metrics"] = metrics_data
    else:
        demo_window_data: dict[str, Any] | None = None
        if validation_run.demo_window is not None:
            demo_window_data = {
                "startedAt": validation_run.demo_window.started_at,
                "endedAt": validation_run.demo_window.ended_at,
                "demoPeriodDays": validation_run.demo_window.demo_period_days,
            }
        data["demoWindow"] = demo_window_data
        data["promotable"] = validation_run.promotable

    return data


def _deserialize(data: dict[str, Any]) -> ValidationRun:
    """Reconstruct ValidationRun entity from Firestore document."""
    collection_name = BACKTEST_COLLECTION_NAME if data.get("runType") == "backtest" else DEMO_COLLECTION_NAME
    try:
        run_type = RunType(data["runType"])

        metrics: PerformanceMetrics | None = None
        demo_window: DemoWindow | None = None
        promotable: bool | None = None

        if run_type == RunType.BACKTEST:
            metrics_data = data.get("metrics")
            if metrics_data is not None:
                metrics = PerformanceMetrics(
                    cost_adjusted_return=float(metrics_data["costAdjustedReturn"]),
                    dsr=float(metrics_data["dsr"]),
                    pbo=float(metrics_data["pbo"]),
                )
        else:
            demo_window_data = data.get("demoWindow")
            if demo_window_data is not None:
                started_at = demo_window_data["startedAt"]
                ended_at = demo_window_data["endedAt"]
                if not isinstance(started_at, datetime.datetime):
                    started_at = datetime.datetime.fromisoformat(str(started_at))
                if not isinstance(ended_at, datetime.datetime):
                    ended_at = datetime.datetime.fromisoformat(str(ended_at))
                demo_window = DemoWindow(
                    started_at=started_at,
                    ended_at=ended_at,
                    demo_period_days=int(demo_window_data["demoPeriodDays"]),
                )
            raw_promotable = data.get("promotable")
            promotable = bool(raw_promotable) if raw_promotable is not None else None

        executed_at = data["executedAt"]
        if not isinstance(executed_at, datetime.datetime):
            executed_at = datetime.datetime.fromisoformat(str(executed_at))

        return ValidationRun(
            identifier=data["identifier"],
            hypothesis=data["hypothesis"],
            run_type=run_type,
            executed_at=executed_at,
            metrics=metrics,
            demo_window=demo_window,
            promotable=promotable,
        )
    except (KeyError, ValueError) as error:
        raise InfrastructureDataFormatError(
            source=collection_name,
            detail=f"Failed to deserialize document: {error}",
            cause=error,
        ) from error
