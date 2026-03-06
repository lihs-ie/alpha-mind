"""FailureDetail value object - failure information with reason code."""

from __future__ import annotations

from dataclasses import dataclass

from domain.value_object.enums import ReasonCode


@dataclass(frozen=True)
class FailureDetail:
    """Detailed failure information including reason code and retryability."""

    reason_code: ReasonCode
    detail: str | None
    retryable: bool

    def __post_init__(self) -> None:
        if self.reason_code is None:
            raise ValueError("reason_code must not be None")
