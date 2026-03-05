"""Cloud Storage signal writer for writing Parquet signal files."""

import io

import pandas
from google.cloud.storage import Client as StorageClient

from signal_generator.domain.ports.signal_writer import SignalWriter
from signal_generator.infrastructure.retry import with_retry
from signal_generator.infrastructure.storage.gs_uri_parser import parse_gs_uri


class CloudStorageSignalWriter(SignalWriter):
    """signal_store バケットに推論結果 Parquet を書き出す。"""

    def __init__(self, storage_client: StorageClient) -> None:
        self._storage_client = storage_client

    def write(self, dataframe: pandas.DataFrame, storage_path: str) -> None:
        """DataFrame を Parquet 形式で gs:// URI に書き出す。"""
        bucket_name, object_path = parse_gs_uri(storage_path)
        bucket = self._storage_client.bucket(bucket_name)
        blob = bucket.blob(object_path)

        buffer = io.BytesIO()
        dataframe.to_parquet(buffer, index=False)

        def _upload() -> None:
            buffer.seek(0)
            blob.upload_from_file(buffer, content_type="application/octet-stream")

        with_retry(_upload)
