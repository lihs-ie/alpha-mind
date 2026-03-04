"""Tests for CloudStorageSignalWriter."""

from unittest.mock import MagicMock

import pytest

from signal_generator.infrastructure.storage.cloud_storage_signal_writer import (
    CloudStorageSignalWriter,
)


class TestCloudStorageSignalWriter:
    """CloudStorageSignalWriter のテスト。"""

    def test_write_uploads_dataframe_as_parquet(self) -> None:
        mock_storage_client = MagicMock()
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_bucket.blob.return_value = mock_blob
        mock_storage_client.bucket.return_value = mock_bucket

        mock_dataframe = MagicMock()

        writer = CloudStorageSignalWriter(storage_client=mock_storage_client)
        writer.write(
            mock_dataframe, "gs://signal-bucket/signals/2026-03-05.parquet"
        )

        mock_storage_client.bucket.assert_called_once_with("signal-bucket")
        mock_bucket.blob.assert_called_once_with("signals/2026-03-05.parquet")
        mock_dataframe.to_parquet.assert_called_once()
        mock_blob.upload_from_file.assert_called_once()

    def test_write_raises_value_error_for_invalid_uri(self) -> None:
        mock_storage_client = MagicMock()
        writer = CloudStorageSignalWriter(storage_client=mock_storage_client)
        mock_dataframe = MagicMock()

        with pytest.raises(ValueError, match="gs://"):
            writer.write(mock_dataframe, "https://example.com/signals.parquet")

    def test_write_sets_content_type_to_parquet(self) -> None:
        mock_storage_client = MagicMock()
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_bucket.blob.return_value = mock_blob
        mock_storage_client.bucket.return_value = mock_bucket

        mock_dataframe = MagicMock()

        writer = CloudStorageSignalWriter(storage_client=mock_storage_client)
        writer.write(
            mock_dataframe, "gs://signal-bucket/signals/2026-03-05.parquet"
        )

        upload_call = mock_blob.upload_from_file.call_args
        assert upload_call[1]["content_type"] == "application/octet-stream"
