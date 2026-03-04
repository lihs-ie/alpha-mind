"""Cloud Storage feature reader for reading Parquet feature files."""

import io

import pandas
from google.cloud.storage import Client as StorageClient

from signal_generator.infrastructure.storage.gs_uri_parser import parse_gs_uri


class CloudStorageFeatureReader:
    """feature_store バケットから Parquet 特徴量ファイルを読み込む。"""

    def __init__(self, storage_client: StorageClient) -> None:
        self._storage_client = storage_client

    def read(self, storage_path: str) -> pandas.DataFrame:
        """gs:// URI から Parquet ファイルを読み込み DataFrame として返す。"""
        bucket_name, object_path = parse_gs_uri(storage_path)
        bucket = self._storage_client.bucket(bucket_name)
        blob = bucket.blob(object_path)
        parquet_bytes = blob.download_as_bytes()
        return pandas.read_parquet(io.BytesIO(parquet_bytes))
