"""Tests for CloudStorageFeatureReader."""

from unittest.mock import MagicMock, patch

import pytest

from signal_generator.infrastructure.storage.cloud_storage_feature_reader import (
    CloudStorageFeatureReader,
)


class TestCloudStorageFeatureReader:
    """CloudStorageFeatureReader のテスト。"""

    def test_read_parses_gs_uri_and_downloads_blob(self) -> None:
        mock_storage_client = MagicMock()
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_blob.download_as_bytes.return_value = b"parquet-bytes"
        mock_bucket.blob.return_value = mock_blob
        mock_storage_client.bucket.return_value = mock_bucket

        reader = CloudStorageFeatureReader(storage_client=mock_storage_client)

        with patch(
            "signal_generator.infrastructure.storage.cloud_storage_feature_reader.pandas.read_parquet"
        ) as mock_read_parquet:
            mock_dataframe = MagicMock()
            mock_read_parquet.return_value = mock_dataframe

            result = reader.read("gs://feature-bucket/features/2026-03-05.parquet")

            mock_storage_client.bucket.assert_called_once_with("feature-bucket")
            mock_bucket.blob.assert_called_once_with("features/2026-03-05.parquet")
            mock_blob.download_as_bytes.assert_called_once()
            mock_read_parquet.assert_called_once()
            assert result is mock_dataframe

    def test_read_raises_value_error_for_invalid_uri(self) -> None:
        mock_storage_client = MagicMock()
        reader = CloudStorageFeatureReader(storage_client=mock_storage_client)

        with pytest.raises(ValueError, match="gs://"):
            reader.read("https://example.com/not-a-gs-uri")

    def test_read_raises_value_error_for_uri_without_path(self) -> None:
        mock_storage_client = MagicMock()
        reader = CloudStorageFeatureReader(storage_client=mock_storage_client)

        with pytest.raises(ValueError, match="オブジェクトパス"):
            reader.read("gs://bucket-only")

    def test_read_with_nested_path(self) -> None:
        mock_storage_client = MagicMock()
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_blob.download_as_bytes.return_value = b"parquet-bytes"
        mock_bucket.blob.return_value = mock_blob
        mock_storage_client.bucket.return_value = mock_bucket

        reader = CloudStorageFeatureReader(storage_client=mock_storage_client)

        with patch(
            "signal_generator.infrastructure.storage.cloud_storage_feature_reader.pandas.read_parquet"
        ) as mock_read_parquet:
            mock_read_parquet.return_value = MagicMock()

            reader.read("gs://my-bucket/path/to/nested/features.parquet")

            mock_storage_client.bucket.assert_called_once_with("my-bucket")
            mock_bucket.blob.assert_called_once_with("path/to/nested/features.parquet")
