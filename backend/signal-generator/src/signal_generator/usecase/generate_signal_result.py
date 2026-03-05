"""GenerateSignalResult DTO."""

from __future__ import annotations

from dataclasses import dataclass

from signal_generator.domain.enums.reason_code import ReasonCode


@dataclass(frozen=True)
class GenerateSignalResult:
    """ユースケース処理結果 DTO。

    呼び出し元に処理の成否と詳細を返す。
    """

    is_success: bool
    is_duplicate: bool = False
    reason_code: ReasonCode | None = None
    detail: str | None = None

    @classmethod
    def success(cls) -> GenerateSignalResult:
        """正常完了の結果を返す。"""
        return cls(is_success=True, is_duplicate=False)

    @classmethod
    def duplicate(cls) -> GenerateSignalResult:
        """冪等性チェックで重複検出した結果を返す。"""
        return cls(is_success=True, is_duplicate=True)

    @classmethod
    def failure(cls, reason_code: ReasonCode, detail: str | None = None) -> GenerateSignalResult:
        """失敗の結果を返す。"""
        return cls(is_success=False, is_duplicate=False, reason_code=reason_code, detail=detail)
