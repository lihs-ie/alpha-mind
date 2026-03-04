"""Cloud Storage implementation of FeatureArtifactRepository."""

from __future__ import annotations

import json
from typing import Any

from google.cloud.storage import Client

from domain.repository.feature_artifact_repository import FeatureArtifactRepository
from domain.value_object.feature_artifact import FeatureArtifact


class CloudStorageFeatureArtifactRepository(FeatureArtifactRepository):
    """Cloud Storage-backed repository for feature artifact metadata.

    Stores metadata JSON alongside the Parquet feature file.
    The Parquet file itself is written by the feature pipeline;
    this repository manages the metadata sidecar.
    """

    def __init__(self, client: Client, bucket_name: str) -> None:
        self._client = client
        self._bucket_name = bucket_name

    def persist(self, feature_artifact: FeatureArtifact) -> None:
        metadata = _serialize(feature_artifact)
        blob = self._client.bucket(self._bucket_name).blob(
            f"{feature_artifact.feature_version}/metadata.json"
        )
        blob.upload_from_string(
            json.dumps(metadata),
            content_type="application/json",
        )

    def find(self, feature_version: str) -> FeatureArtifact | None:
        blob = self._client.bucket(self._bucket_name).blob(
            f"{feature_version}/metadata.json"
        )
        if not blob.exists():
            return None
        content = blob.download_as_text()
        data: dict[str, Any] = json.loads(content)
        return _deserialize(data)

    def terminate(self, feature_version: str) -> None:
        bucket = self._client.bucket(self._bucket_name)
        blobs = bucket.list_blobs(prefix=f"{feature_version}/")
        for blob in blobs:
            blob.delete()


def _serialize(artifact: FeatureArtifact) -> dict[str, Any]:
    return {
        "featureVersion": artifact.feature_version,
        "storagePath": artifact.storage_path,
        "rowCount": artifact.row_count,
        "featureCount": artifact.feature_count,
    }


def _deserialize(data: dict[str, Any]) -> FeatureArtifact:
    return FeatureArtifact(
        feature_version=data["featureVersion"],
        storage_path=data["storagePath"],
        row_count=data["rowCount"],
        feature_count=data["featureCount"],
    )
