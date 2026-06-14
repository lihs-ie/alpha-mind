"""FailureSummary value object."""

from dataclasses import dataclass, field

from hypothesis_lab.domain.enums.reason_code import ReasonCode


@dataclass(frozen=True)
class FailureSummary:
    """失敗知見の内容。

    INV: 全フィールド必須。markdown_summary は空文字列不可。
    Value Object として値比較で等価判定し、immutable。
    """

    reason_code: ReasonCode
    markdown_summary: str

    def __post_init__(self) -> None:
        if not self.markdown_summary:
            raise ValueError("markdown_summary は空文字列にできません")
