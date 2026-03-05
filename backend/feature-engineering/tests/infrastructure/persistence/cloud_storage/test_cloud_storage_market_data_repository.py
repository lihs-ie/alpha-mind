"""Tests for CloudStorageMarketDataRepository."""

import datetime
import json
from unittest.mock import MagicMock

import pytest

from domain.value_object.enums import SourceStatusValue
from domain.value_object.market_snapshot import MarketSnapshot
from infrastructure.error import InfrastructureDataFormatError
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

    def test_find_by_target_date_returns_latest_when_multiple_matches(self) -> None:
        mock_client = MagicMock()
        mock_bucket = MagicMock()
        mock_client.bucket.return_value = mock_bucket

        earlier_ulid = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
        later_ulid = "01BRZ3NDEKTSV4RRFFQ69G5FAV"

        mock_earlier_blob = MagicMock()
        mock_earlier_blob.name = f"{earlier_ulid}/metadata.json"
        mock_earlier_blob.download_as_text.return_value = json.dumps(
            {
                "identifier": earlier_ulid,
                "targetDate": "2026-01-15",
                "storagePath": f"gs://raw_market_data/{earlier_ulid}/market.parquet",
                "sourceStatus": {"jp": "ok", "us": "failed"},
            }
        )

        mock_later_blob = MagicMock()
        mock_later_blob.name = f"{later_ulid}/metadata.json"
        mock_later_blob.download_as_text.return_value = json.dumps(
            {
                "identifier": later_ulid,
                "targetDate": "2026-01-15",
                "storagePath": f"gs://raw_market_data/{later_ulid}/market.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            }
        )

        # Provide earlier blob first to ensure sorting, not insertion order, determines result
        mock_bucket.list_blobs.return_value = [mock_earlier_blob, mock_later_blob]

        repository = CloudStorageMarketDataRepository(
            client=mock_client,
            bucket_name="raw_market_data",
        )
        result = repository.find_by_target_date(datetime.date(2026, 1, 15))

        assert result is not None
        assert result.storage_path == f"gs://raw_market_data/{later_ulid}/market.parquet"
        assert result.source_status.us == SourceStatusValue.OK

    def test_find_by_target_date_skips_corrupt_metadata_and_returns_valid(self) -> None:
        mock_client = MagicMock()
        mock_bucket = MagicMock()
        mock_client.bucket.return_value = mock_bucket

        corrupt_blob = MagicMock()
        corrupt_blob.name = "corrupt_ulid/metadata.json"
        corrupt_blob.download_as_text.return_value = "NOT VALID JSON{{"

        valid_blob = MagicMock()
        valid_blob.name = "valid_ulid/metadata.json"
        valid_blob.download_as_text.return_value = json.dumps(
            {
                "identifier": VALID_ULID,
                "targetDate": "2026-01-15",
                "storagePath": "gs://raw_market_data/valid_ulid/market.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            }
        )

        mock_bucket.list_blobs.return_value = [corrupt_blob, valid_blob]

        repository = CloudStorageMarketDataRepository(
            client=mock_client,
            bucket_name="raw_market_data",
        )
        result = repository.find_by_target_date(datetime.date(2026, 1, 15))

        assert result is not None
        assert isinstance(result, MarketSnapshot)
        assert result.target_date == datetime.date(2026, 1, 15)
        assert result.storage_path == "gs://raw_market_data/valid_ulid/market.parquet"

    def test_find_by_target_date_returns_none_when_all_corrupt(self) -> None:
        mock_client = MagicMock()
        mock_bucket = MagicMock()
        mock_client.bucket.return_value = mock_bucket

        corrupt_blob_1 = MagicMock()
        corrupt_blob_1.name = "corrupt1/metadata.json"
        corrupt_blob_1.download_as_text.return_value = "{{invalid json"

        corrupt_blob_2 = MagicMock()
        corrupt_blob_2.name = "corrupt2/metadata.json"
        corrupt_blob_2.download_as_text.return_value = "also not json!!"

        mock_bucket.list_blobs.return_value = [corrupt_blob_1, corrupt_blob_2]

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


class TestCloudStorageMarketDataRepositoryDeserializeErrors:
    def test_find_raises_for_invalid_json(self) -> None:
        mock_client = MagicMock()
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_client.bucket.return_value = mock_bucket
        mock_bucket.blob.return_value = mock_blob
        mock_blob.exists.return_value = True
        mock_blob.download_as_text.return_value = "NOT VALID JSON{{"

        repository = CloudStorageMarketDataRepository(
            client=mock_client,
            bucket_name="raw_market_data",
        )
        with pytest.raises(InfrastructureDataFormatError):
            repository.find("01ARZ3NDEKTSV4RRFFQ69G5FAV")

    def test_find_raises_for_missing_source_status(self) -> None:
        mock_client = MagicMock()
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_client.bucket.return_value = mock_bucket
        mock_bucket.blob.return_value = mock_blob
        mock_blob.exists.return_value = True
        mock_blob.download_as_text.return_value = json.dumps(
            {
                "identifier": "01ARZ3NDEKTSV4RRFFQ69G5FAV",
                "targetDate": "2026-01-15",
                "storagePath": "gs://test/path",
                # "sourceStatus" is missing
            }
        )

        repository = CloudStorageMarketDataRepository(
            client=mock_client,
            bucket_name="raw_market_data",
        )
        with pytest.raises(InfrastructureDataFormatError):
            repository.find("01ARZ3NDEKTSV4RRFFQ69G5FAV")
