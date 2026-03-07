"""Tests for environment helpers."""

from __future__ import annotations

import os

import pytest

from alpha_mind_backend_common.runtime.env import require_env


def test_require_env_returns_value(monkeypatch: pytest.MonkeyPatch) -> None:
    """Returns the environment variable value when present."""
    monkeypatch.setenv("TEST_REQUIRED_ENV", "configured")

    assert require_env("TEST_REQUIRED_ENV") == "configured"


def test_require_env_raises_when_missing(monkeypatch: pytest.MonkeyPatch) -> None:
    """Raises OSError when the environment variable is missing."""
    monkeypatch.delenv("TEST_REQUIRED_ENV", raising=False)

    with pytest.raises(OSError, match="TEST_REQUIRED_ENV"):
        require_env("TEST_REQUIRED_ENV")


def test_require_env_raises_when_empty(monkeypatch: pytest.MonkeyPatch) -> None:
    """Raises OSError when the environment variable is empty."""
    monkeypatch.setenv("TEST_REQUIRED_ENV", "")

    with pytest.raises(OSError, match="TEST_REQUIRED_ENV"):
        require_env("TEST_REQUIRED_ENV")
