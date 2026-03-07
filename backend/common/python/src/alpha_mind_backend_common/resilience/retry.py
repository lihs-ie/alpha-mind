"""Retry utility with exponential backoff."""

from __future__ import annotations

import logging
import time
from collections.abc import Callable
from typing import TypeVar

from google.api_core.exceptions import (
    DeadlineExceeded,
    GoogleAPICallError,
    InternalServerError,
    ServiceUnavailable,
    TooManyRequests,
)

logger = logging.getLogger(__name__)
T = TypeVar("T")

_MAX_RETRIES = 3
_BASE_DELAY_SECONDS = 1.0
_RETRYABLE_EXCEPTIONS = (
    ServiceUnavailable,
    InternalServerError,
    DeadlineExceeded,
    TooManyRequests,
    ConnectionError,
    TimeoutError,
)


def with_retry(  # noqa: UP047
    operation: Callable[[], T],
    max_retries: int = _MAX_RETRIES,
    base_delay: float = _BASE_DELAY_SECONDS,
) -> T:
    """Execute an operation with exponential backoff retries."""
    last_exception: Exception | None = None
    for attempt in range(max_retries + 1):
        try:
            return operation()
        except _RETRYABLE_EXCEPTIONS as error:
            last_exception = error
            if attempt < max_retries:
                delay = base_delay * (2**attempt)
                logger.warning(
                    "Transient failure (attempt %d/%d), retrying in %.1fs: %s",
                    attempt + 1,
                    max_retries,
                    delay,
                    error,
                )
                time.sleep(delay)
            else:
                logger.error("All %d retries exhausted: %s", max_retries, error)
        except GoogleAPICallError:
            raise

    assert last_exception is not None
    raise last_exception
