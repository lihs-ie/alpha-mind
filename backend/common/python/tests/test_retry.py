"""Tests for retry helpers."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest
from google.api_core.exceptions import (
    DeadlineExceeded,
    InternalServerError,
    NotFound,
    ServiceUnavailable,
    TooManyRequests,
)

from alpha_mind_backend_common.resilience.retry import with_retry


def test_with_retry_returns_result_on_success() -> None:
    """Returns the operation result when the first call succeeds."""
    assert with_retry(lambda: "ok") == "ok"


def test_with_retry_retries_on_retryable_errors() -> None:
    """Retries on transient Google API errors."""
    operation = MagicMock(side_effect=[ServiceUnavailable("down"), "ok"])

    with patch("alpha_mind_backend_common.resilience.retry.time.sleep"):
        result = with_retry(operation, base_delay=0.01)

    assert result == "ok"
    assert operation.call_count == 2


def test_with_retry_retries_on_connection_error() -> None:
    """Retries on ConnectionError."""
    operation = MagicMock(side_effect=[ConnectionError("refused"), "ok"])

    with patch("alpha_mind_backend_common.resilience.retry.time.sleep"):
        result = with_retry(operation, base_delay=0.01)

    assert result == "ok"


def test_with_retry_retries_on_timeout_error() -> None:
    """Retries on TimeoutError."""
    operation = MagicMock(side_effect=[TimeoutError("slow"), "ok"])

    with patch("alpha_mind_backend_common.resilience.retry.time.sleep"):
        result = with_retry(operation, base_delay=0.01)

    assert result == "ok"


def test_with_retry_retries_on_other_google_retryable_errors() -> None:
    """Retries on other configured Google API transient errors."""
    for error in [InternalServerError("internal"), DeadlineExceeded("late"), TooManyRequests("busy")]:
        operation = MagicMock(side_effect=[error, "ok"])
        with patch("alpha_mind_backend_common.resilience.retry.time.sleep"):
            result = with_retry(operation, base_delay=0.01)
        assert result == "ok"


def test_with_retry_raises_after_max_retries() -> None:
    """Raises the last retryable exception after exhausting retries."""
    operation = MagicMock(side_effect=[ServiceUnavailable("fail")] * 4)

    with patch("alpha_mind_backend_common.resilience.retry.time.sleep"), pytest.raises(ServiceUnavailable):
        with_retry(operation, max_retries=3, base_delay=0.01)

    assert operation.call_count == 4


def test_with_retry_does_not_retry_on_permanent_error() -> None:
    """Does not retry on non-retryable exceptions."""
    operation = MagicMock(side_effect=NotFound("missing"))

    with pytest.raises(NotFound):
        with_retry(operation)

    assert operation.call_count == 1
