"""Tests for retry utility."""

from unittest.mock import MagicMock, patch

import pytest
from google.api_core.exceptions import (
    DeadlineExceeded,
    InternalServerError,
    NotFound,
    ServiceUnavailable,
    TooManyRequests,
)

from signal_generator.infrastructure.retry import with_retry


class TestWithRetry:
    """with_retry のテスト。"""

    def test_returns_result_on_success(self) -> None:
        result = with_retry(lambda: "ok")
        assert result == "ok"

    def test_retries_on_service_unavailable(self) -> None:
        mock_operation = MagicMock(side_effect=[ServiceUnavailable("unavailable"), "ok"])
        with patch("signal_generator.infrastructure.retry.time.sleep"):
            result = with_retry(mock_operation, base_delay=0.01)
        assert result == "ok"
        assert mock_operation.call_count == 2

    def test_retries_on_connection_error(self) -> None:
        mock_operation = MagicMock(side_effect=[ConnectionError("conn refused"), "ok"])
        with patch("signal_generator.infrastructure.retry.time.sleep"):
            result = with_retry(mock_operation, base_delay=0.01)
        assert result == "ok"

    def test_retries_on_timeout_error(self) -> None:
        mock_operation = MagicMock(side_effect=[TimeoutError("timeout"), "ok"])
        with patch("signal_generator.infrastructure.retry.time.sleep"):
            result = with_retry(mock_operation, base_delay=0.01)
        assert result == "ok"

    def test_raises_after_max_retries_exhausted(self) -> None:
        mock_operation = MagicMock(
            side_effect=[ServiceUnavailable("fail")] * 4,
        )
        with patch("signal_generator.infrastructure.retry.time.sleep"), pytest.raises(ServiceUnavailable):
            with_retry(mock_operation, max_retries=3, base_delay=0.01)
        assert mock_operation.call_count == 4

    def test_retries_on_internal_server_error(self) -> None:
        mock_operation = MagicMock(side_effect=[InternalServerError("internal"), "ok"])
        with patch("signal_generator.infrastructure.retry.time.sleep"):
            result = with_retry(mock_operation, base_delay=0.01)
        assert result == "ok"

    def test_retries_on_deadline_exceeded(self) -> None:
        mock_operation = MagicMock(side_effect=[DeadlineExceeded("deadline"), "ok"])
        with patch("signal_generator.infrastructure.retry.time.sleep"):
            result = with_retry(mock_operation, base_delay=0.01)
        assert result == "ok"

    def test_retries_on_too_many_requests(self) -> None:
        mock_operation = MagicMock(side_effect=[TooManyRequests("rate limit"), "ok"])
        with patch("signal_generator.infrastructure.retry.time.sleep"):
            result = with_retry(mock_operation, base_delay=0.01)
        assert result == "ok"

    def test_does_not_retry_on_permanent_error(self) -> None:
        mock_operation = MagicMock(side_effect=NotFound("not found"))
        with pytest.raises(NotFound):
            with_retry(mock_operation)
        assert mock_operation.call_count == 1
