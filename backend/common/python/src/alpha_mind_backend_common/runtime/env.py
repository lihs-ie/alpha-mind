"""Environment variable helpers."""

from __future__ import annotations

import os


def require_env(name: str) -> str:
    """Return the required environment variable value.

    Raises:
        OSError: If the environment variable is missing or empty.
    """
    value = os.environ.get(name)
    if not value:
        raise OSError(f"Required environment variable '{name}' is not set")
    return value
