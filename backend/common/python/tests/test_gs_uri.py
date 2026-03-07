"""Tests for gs:// URI parsing."""

from __future__ import annotations

import pytest

from alpha_mind_backend_common.storage.gs_uri import parse_gs_uri


def test_parse_gs_uri_returns_bucket_and_object_path() -> None:
    """Parses a valid gs:// URI."""
    bucket_name, object_path = parse_gs_uri("gs://feature-bucket/path/to/file.parquet")

    assert bucket_name == "feature-bucket"
    assert object_path == "path/to/file.parquet"


def test_parse_gs_uri_rejects_non_gs_scheme() -> None:
    """Rejects URIs that do not use the gs:// scheme."""
    with pytest.raises(ValueError, match="gs://"):
        parse_gs_uri("https://example.com/file.parquet")


def test_parse_gs_uri_rejects_missing_object_path() -> None:
    """Rejects URIs without an object path."""
    with pytest.raises(ValueError, match="オブジェクトパス"):
        parse_gs_uri("gs://bucket-only")


def test_parse_gs_uri_rejects_empty_bucket_name() -> None:
    """Rejects URIs with an empty bucket name."""
    with pytest.raises(ValueError, match="バケット名が空"):
        parse_gs_uri("gs:///path/to/file.parquet")


def test_parse_gs_uri_rejects_empty_object_path() -> None:
    """Rejects URIs with an empty object path."""
    with pytest.raises(ValueError, match="オブジェクトパスが空"):
        parse_gs_uri("gs://feature-bucket/")
