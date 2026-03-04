"""Tests for CloudStorageFeatureArtifactRepository."""

import io
from unittest.mock import MagicMock

import pyarrow as pa
import pyarrow.parquet as pq

from domain.value_object.feature_artifact import FeatureArtifact
from infrastructure.persistence.cloud_storage.cloud_storage_feature_artifact_repository import (
    CloudStorageFeatureArtifactRepository,
)


def _make_artifact() -> FeatureArtifact:
    return FeatureArtifact(
        feature_version="v20260115-001",
        storage_path="gs://feature_store/v20260115-001/features.parquet",
        row_count=3,
        feature_count=2,
    )


def _make_parquet_bytes() -> bytes:
    """Create minimal Parquet bytes for testing."""
    table = pa.table({"feature_a": [1.0, 2.0, 3.0], "feature_b": [4.0, 5.0, 6.0]})
    buffer = io.BytesIO()
    pq.write_table(table, buffer)
    return buffer.getvalue()


class TestCloudStorageFeatureArtifactRepositoryPersist:
    def test_persist_uploads_parquet_metadata(self) -> None:
        mock_storage_client = MagicMock()
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_storage_client.bucket.return_value = mock_bucket
        mock_bucket.blob.return_value = mock_blob

        repository = CloudStorageFeatureArtifactRepository(
            client=mock_storage_client,
            bucket_name="feature_store",
        )
        artifact = _make_artifact()
        repository.persist(artifact)

        mock_storage_client.bucket.assert_called_once_with("feature_store")
        mock_bucket.blob.assert_called_once_with("v20260115-001/metadata.json")
        mock_blob.upload_from_string.assert_called_once()

        # Verify the metadata content
        import json

        uploaded_content = mock_blob.upload_from_string.call_args[0][0]
        metadata = json.loads(uploaded_content)
        assert metadata["featureVersion"] == "v20260115-001"
        assert metadata["storagePath"] == "gs://feature_store/v20260115-001/features.parquet"
        assert metadata["rowCount"] == 3
        assert metadata["featureCount"] == 2


class TestCloudStorageFeatureArtifactRepositoryFind:
    def test_find_returns_none_when_not_found(self) -> None:
        mock_storage_client = MagicMock()
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_storage_client.bucket.return_value = mock_bucket
        mock_bucket.blob.return_value = mock_blob
        mock_blob.exists.return_value = False

        repository = CloudStorageFeatureArtifactRepository(
            client=mock_storage_client,
            bucket_name="feature_store",
        )
        result = repository.find("v20260115-001")

        assert result is None

    def test_find_returns_artifact_from_metadata(self) -> None:
        import json

        mock_storage_client = MagicMock()
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_storage_client.bucket.return_value = mock_bucket
        mock_bucket.blob.return_value = mock_blob
        mock_blob.exists.return_value = True

        metadata = {
            "featureVersion": "v20260115-001",
            "storagePath": "gs://feature_store/v20260115-001/features.parquet",
            "rowCount": 3,
            "featureCount": 2,
        }
        mock_blob.download_as_text.return_value = json.dumps(metadata)

        repository = CloudStorageFeatureArtifactRepository(
            client=mock_storage_client,
            bucket_name="feature_store",
        )
        result = repository.find("v20260115-001")

        assert result is not None
        assert result.feature_version == "v20260115-001"
        assert result.storage_path == "gs://feature_store/v20260115-001/features.parquet"
        assert result.row_count == 3
        assert result.feature_count == 2


class TestCloudStorageFeatureArtifactRepositoryTerminate:
    def test_terminate_deletes_metadata_blob(self) -> None:
        mock_storage_client = MagicMock()
        mock_bucket = MagicMock()
        mock_storage_client.bucket.return_value = mock_bucket

        # Simulate listing blobs with a prefix
        mock_blob1 = MagicMock()
        mock_blob2 = MagicMock()
        mock_bucket.list_blobs.return_value = [mock_blob1, mock_blob2]

        repository = CloudStorageFeatureArtifactRepository(
            client=mock_storage_client,
            bucket_name="feature_store",
        )
        repository.terminate("v20260115-001")

        mock_bucket.list_blobs.assert_called_once_with(prefix="v20260115-001/")
        mock_blob1.delete.assert_called_once()
        mock_blob2.delete.assert_called_once()
