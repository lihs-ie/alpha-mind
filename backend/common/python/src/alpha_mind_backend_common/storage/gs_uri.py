"""Helpers for gs:// URIs."""

from __future__ import annotations


def parse_gs_uri(uri: str) -> tuple[str, str]:
    """Split a gs:// URI into bucket name and object path."""
    if not uri.startswith("gs://"):
        raise ValueError(f"Cloud Storage URI は gs:// で始まる必要がある (got: {uri})")

    without_prefix = uri[len("gs://") :]
    slash_index = without_prefix.find("/")
    if slash_index == -1:
        raise ValueError(f"Cloud Storage URI にオブジェクトパスが含まれていない (got: {uri})")

    bucket_name = without_prefix[:slash_index]
    object_path = without_prefix[slash_index + 1 :]

    if not bucket_name:
        raise ValueError(f"Cloud Storage URI のバケット名が空 (got: {uri})")
    if not object_path:
        raise ValueError(f"Cloud Storage URI のオブジェクトパスが空 (got: {uri})")

    return bucket_name, object_path
