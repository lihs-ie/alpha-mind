"""Firestore implementation of InsightRecordRepository (read-only)."""

from __future__ import annotations

import datetime
from typing import Any

from google.cloud.firestore_v1 import Client, FieldFilter

from domain.repository.insight_record_repository import InsightRecordRepository
from domain.value_object.insight_snapshot import InsightSnapshot

COLLECTION_NAME = "insight_records"


class FirestoreInsightRecordRepository(InsightRecordRepository):
    """Read-only Firestore-backed repository for insight records.

    Aggregates raw insight_records documents into InsightSnapshot value objects
    that the feature-engineering domain needs for point-in-time consistency checks.
    """

    def __init__(self, client: Client) -> None:
        self._client = client

    def search(self, target_date: datetime.date | None = None) -> list[InsightSnapshot]:
        if target_date is not None:
            documents = self._query_by_target_date(target_date)
            snapshot = _build_snapshot(documents, filtered_by_target_date=True)
        else:
            collection_reference = self._client.collection(COLLECTION_NAME)
            documents = [data for document in collection_reference.stream() if (data := document.to_dict()) is not None]
            snapshot = _build_snapshot(documents, filtered_by_target_date=False)
        return [snapshot]

    def find_by_target_date(self, target_date: datetime.date) -> InsightSnapshot | None:
        documents = self._query_by_target_date(target_date)
        if not documents:
            return None
        return _build_snapshot(documents, filtered_by_target_date=True)

    def _query_by_target_date(self, target_date: datetime.date) -> list[dict[str, Any]]:
        """Query insight_records where collectedAt falls within the given date (UTC)."""
        start_of_day = datetime.datetime(target_date.year, target_date.month, target_date.day, tzinfo=datetime.UTC)
        end_of_day = start_of_day + datetime.timedelta(days=1)

        query = (
            self._client.collection(COLLECTION_NAME)
            .where(filter=FieldFilter("collectedAt", ">=", start_of_day))
            .where(filter=FieldFilter("collectedAt", "<", end_of_day))
        )
        return [data for document in query.stream() if (data := document.to_dict()) is not None]


def _build_snapshot(
    documents: list[dict[str, Any]],
    filtered_by_target_date: bool,
) -> InsightSnapshot:
    """Build an InsightSnapshot from a list of raw Firestore documents."""
    record_count = len(documents)

    latest_collected_at: datetime.datetime | None = None
    if record_count > 0:
        collected_timestamps = [document["collectedAt"] for document in documents]
        latest_collected_at = max(collected_timestamps)

    return InsightSnapshot(
        record_count=record_count,
        latest_collected_at=latest_collected_at,
        filtered_by_target_date=filtered_by_target_date,
    )
