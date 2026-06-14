"""FailureSummary value object."""

from __future__ import annotations

from dataclasses import dataclass, field

from domain.value_object.enums import ReasonCode


@dataclass(frozen=True)
class FailureSummary:
    """Immutable value object capturing failure knowledge for a hypothesis.

    Attributes:
        reason_code: Categorised reason for failure.
        markdown_summary: Human-readable Markdown explanation of the failure.
    """

    reason_code: ReasonCode
    markdown_summary: str = field()

    def __post_init__(self) -> None:
        if not self.markdown_summary:
            raise ValueError("FailureSummary.markdown_summary must not be empty")
