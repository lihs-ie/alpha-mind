"""Cloud Storage implementation of MarketDataRepository (read-only)."""

from __future__ import annotations

import datetime
import json
import logging
from typing import Any

from google.cloud.storage import Client

from domain.repository.market_data_repository import MarketDataRepository
from domain.value_object.enums import SourceStatusValue
from domain.value_object.market_snapshot import MarketSnapshot
from domain.value_object.source_status import SourceStatus
from infrastructure.error import InfrastructureDataFormatError

logger = logging.getLogger(__name__)


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
        try:
            data: dict[str, Any] = json.loads(content)
        except json.JSONDecodeError as error:
            raise InfrastructureDataFormatError(
                source=self._bucket_name,
                detail=f"Failed to parse metadata JSON for {identifier}: {error}",
                cause=error,
            ) from error
        return _deserialize(data)

    def find_by_target_date(self, target_date: datetime.date) -> MarketSnapshot | None:
        """Find a market snapshot by target date.

        Limitation: This method performs a full blob scan of the bucket because
        the raw_market_data bucket layout is owned by svc-data-collector and uses
        ULID-based paths ({identifier}/metadata.json). The targetDate is stored
        inside each metadata.json file, not encoded in the blob path, so
        prefix-based filtering is not possible.

        At MVP scale (~365 blobs/year with daily processing), the full scan is
        acceptable. If the bucket grows significantly, consider maintaining a
        date-to-identifier index (e.g. in Firestore) to enable direct lookups.
        """
        bucket = self._client.bucket(self._bucket_name)
        blobs = list(bucket.list_blobs())

        matches: list[tuple[str, dict[str, Any]]] = []

        for blob in blobs:
            if not blob.name.endswith("/metadata.json"):
                continue
            content = blob.download_as_text()
            try:
                data: dict[str, Any] = json.loads(content)
            except json.JSONDecodeError:
                logger.warning("Skipping corrupt metadata: %s", blob.name)
                continue
            if data.get("targetDate") == target_date.isoformat():
                matches.append((blob.name, data))

        if not matches:
            return None

        matches.sort(key=lambda pair: pair[0], reverse=True)
        return _deserialize(matches[0][1])


def _deserialize(data: dict[str, Any]) -> MarketSnapshot:
    try:
        source_status_data = data["sourceStatus"]
        return MarketSnapshot(
            target_date=datetime.date.fromisoformat(data["targetDate"]),
            storage_path=data["storagePath"],
            source_status=SourceStatus(
                jp=SourceStatusValue(source_status_data["jp"]),
                us=SourceStatusValue(source_status_data["us"]),
            ),
        )
    except (KeyError, ValueError) as error:
        raise InfrastructureDataFormatError(
            source="raw_market_data",
            detail=f"Failed to deserialize metadata: {error}",
            cause=error,
        ) from error
