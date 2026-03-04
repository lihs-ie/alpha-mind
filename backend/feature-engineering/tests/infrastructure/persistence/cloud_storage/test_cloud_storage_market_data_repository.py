"""Tests for CloudStorageMarketDataRepository."""

import datetime
import json
from unittest.mock import MagicMock

from domain.value_object.enums import SourceStatusValue
from domain.value_object.market_snapshot import MarketSnapshot
from infrastructure.persistence.cloud_storage.cloud_storage_market_data_repository import (
    CloudStorageMarketDataRepository,
)

VALID_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"


def _make_metadata_json() -> str:
    return json.dumps(
        {
            "identifier": VALID_ULID,
            "targetDate": "2026-01-15",
            "storagePath": "gs://raw_market_data/2026-01-15/market.parquet",
            "sourceStatus": {"jp": "ok", "us": "ok"},
        }
    )


class TestCloudStorageMarketDataRepositoryFind:
    def test_find_returns_none_when_not_found(self) -> None:
        mock_client = MagicMock()
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_client.bucket.return_value = mock_bucket
        mock_bucket.blob.return_value = mock_blob
        mock_blob.exists.return_value = False

        repository = CloudStorageMarketDataRepository(
            client=mock_client,
            bucket_name="raw_market_data",
        )
        result = repository.find(VALID_ULID)

        assert result is None

    def test_find_returns_market_snapshot(self) -> None:
        mock_client = MagicMock()
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_client.bucket.return_value = mock_bucket
        mock_bucket.blob.return_value = mock_blob
        mock_blob.exists.return_value = True
        mock_blob.download_as_text.return_value = _make_metadata_json()

        repository = CloudStorageMarketDataRepository(
            client=mock_client,
            bucket_name="raw_market_data",
        )
        result = repository.find(VALID_ULID)

        assert result is not None
        assert isinstance(result, MarketSnapshot)
        assert result.target_date == datetime.date(2026, 1, 15)
        assert result.storage_path == "gs://raw_market_data/2026-01-15/market.parquet"
        assert result.source_status.jp == SourceStatusValue.OK
        assert result.source_status.us == SourceStatusValue.OK
        mock_bucket.blob.assert_called_with(f"{VALID_ULID}/metadata.json")


class TestCloudStorageMarketDataRepositoryFindByTargetDate:
    def test_find_by_target_date_returns_none_when_no_blobs(self) -> None:
        mock_client = MagicMock()
        mock_bucket = MagicMock()
        mock_client.bucket.return_value = mock_bucket
        mock_bucket.list_blobs.return_value = []

        repository = CloudStorageMarketDataRepository(
            client=mock_client,
            bucket_name="raw_market_data",
        )
        result = repository.find_by_target_date(datetime.date(2026, 1, 15))

        assert result is None
        mock_bucket.list_blobs.assert_called_once()

    def test_find_by_target_date_skips_non_metadata_blobs(self) -> None:
        mock_client = MagicMock()
        mock_bucket = MagicMock()
        mock_client.bucket.return_value = mock_bucket

        mock_parquet_blob = MagicMock()
        mock_parquet_blob.name = "abc123/market.parquet"

        mock_metadata_blob = MagicMock()
        mock_metadata_blob.name = "abc123/metadata.json"
        mock_metadata_blob.download_as_text.return_value = json.dumps(
            {
                "identifier": VALID_ULID,
                "targetDate": "2026-01-15",
                "storagePath": "gs://raw_market_data/abc123/market.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            }
        )
        mock_bucket.list_blobs.return_value = [mock_parquet_blob, mock_metadata_blob]

        repository = CloudStorageMarketDataRepository(
            client=mock_client,
            bucket_name="raw_market_data",
        )
        result = repository.find_by_target_date(datetime.date(2026, 1, 15))

        assert result is not None
        assert result.target_date == datetime.date(2026, 1, 15)

    def test_find_by_target_date_returns_none_when_no_matching_date(self) -> None:
        mock_client = MagicMock()
        mock_bucket = MagicMock()
        mock_client.bucket.return_value = mock_bucket

        mock_metadata_blob = MagicMock()
        mock_metadata_blob.name = "abc123/metadata.json"
        mock_metadata_blob.download_as_text.return_value = json.dumps(
            {
                "identifier": VALID_ULID,
                "targetDate": "2026-01-14",
                "storagePath": "gs://raw_market_data/abc123/market.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            }
        )
        mock_bucket.list_blobs.return_value = [mock_metadata_blob]

        repository = CloudStorageMarketDataRepository(
            client=mock_client,
            bucket_name="raw_market_data",
        )
        result = repository.find_by_target_date(datetime.date(2026, 1, 15))

        assert result is None

    def test_find_by_target_date_returns_snapshot(self) -> None:
        mock_client = MagicMock()
        mock_bucket = MagicMock()
        mock_client.bucket.return_value = mock_bucket

        mock_metadata_blob = MagicMock()
        mock_metadata_blob.name = "abc123/metadata.json"
        mock_metadata_blob.download_as_text.return_value = json.dumps(
            {
                "identifier": VALID_ULID,
                "targetDate": "2026-01-15",
                "storagePath": "gs://raw_market_data/abc123/market.parquet",
                "sourceStatus": {"jp": "ok", "us": "failed"},
            }
        )
        mock_bucket.list_blobs.return_value = [mock_metadata_blob]

        repository = CloudStorageMarketDataRepository(
            client=mock_client,
            bucket_name="raw_market_data",
        )
        result = repository.find_by_target_date(datetime.date(2026, 1, 15))

        assert result is not None
        assert result.target_date == datetime.date(2026, 1, 15)
        assert result.source_status.us == SourceStatusValue.FAILED
