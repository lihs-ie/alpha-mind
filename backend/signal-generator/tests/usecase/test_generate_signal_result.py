"""Tests for GenerateSignalResult DTO."""

from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.usecase.generate_signal_result import GenerateSignalResult


class TestGenerateSignalResultSuccess:
    """成功結果のテスト。"""

    def test_success_factory(self) -> None:
        result = GenerateSignalResult.success()

        assert result.is_success is True
        assert result.is_duplicate is False
        assert result.reason_code is None
        assert result.detail is None


class TestGenerateSignalResultDuplicate:
    """重複検出結果のテスト。"""

    def test_duplicate_factory(self) -> None:
        result = GenerateSignalResult.duplicate()

        assert result.is_success is True
        assert result.is_duplicate is True
        assert result.reason_code is None


class TestGenerateSignalResultFailure:
    """失敗結果のテスト。"""

    def test_failure_factory_with_reason_code(self) -> None:
        result = GenerateSignalResult.failure(
            reason_code=ReasonCode.MODEL_NOT_APPROVED,
        )

        assert result.is_success is False
        assert result.is_duplicate is False
        assert result.reason_code == ReasonCode.MODEL_NOT_APPROVED
        assert result.detail is None

    def test_failure_factory_with_detail(self) -> None:
        result = GenerateSignalResult.failure(
            reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
            detail="Cloud Storage unavailable",
        )

        assert result.is_success is False
        assert result.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE
        assert result.detail == "Cloud Storage unavailable"

    def test_immutability(self) -> None:
        import pytest

        result = GenerateSignalResult.success()

        with pytest.raises(AttributeError):
            result.is_success = False  # type: ignore[misc]
