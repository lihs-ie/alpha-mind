"""Cloud Storage implementation of MarketDataRepository (read-only)."""

from __future__ import annotations

import datetime
import json
from typing import Any

from google.cloud.storage import Client

from domain.repository.market_data_repository import MarketDataRepository
from domain.value_object.enums import SourceStatusValue
from domain.value_object.market_snapshot import MarketSnapshot
from domain.value_object.source_status import SourceStatus


class CloudStorageMarketDataRepository(MarketDataRepository):
    """Read-only Cloud Storage-backed repository for market data.

    Reads metadata JSON from the raw_market_data bucket.
    The actual Parquet data files are managed by svc-data-collector.
    """

    def __init__(self, client: Client, bucket_name: str) -> None:
        self._client = client
        self._bucket_name = bucket_name

    def find(self, identifier: str) -> MarketSnapshot | None:
        blob = self._client.bucket(self._bucket_name).blob(f"{identifier}/metadata.json")
        if not blob.exists():
            return None
        content = blob.download_as_text()
        data: dict[str, Any] = json.loads(content)
        return _deserialize(data)

    def find_by_target_date(self, target_date: datetime.date) -> MarketSnapshot | None:
        prefix = f"{target_date.isoformat()}/"
        bucket = self._client.bucket(self._bucket_name)
        blobs = list(bucket.list_blobs(prefix=prefix, delimiter="/"))

        # Find the metadata.json blob within the date prefix
        for blob in blobs:
            if blob.name.endswith("/metadata.json"):
                content = blob.download_as_text()
                data: dict[str, Any] = json.loads(content)
                return _deserialize(data)
        return None


def _deserialize(data: dict[str, Any]) -> MarketSnapshot:
    source_status_data = data["sourceStatus"]
    return MarketSnapshot(
        target_date=datetime.date.fromisoformat(data["targetDate"]),
        storage_path=data["storagePath"],
        source_status=SourceStatus(
            jp=SourceStatusValue(source_status_data["jp"]),
            us=SourceStatusValue(source_status_data["us"]),
        ),
    )
