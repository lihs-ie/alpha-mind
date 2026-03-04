"""FailureDetail value object."""

from dataclasses import dataclass

from signal_generator.domain.enums.reason_code import ReasonCode


@dataclass(frozen=True)
class FailureDetail:
    """失敗情報。RULE-SG-008: 失敗時に reasonCode を必ず保持する。"""

    reason_code: ReasonCode
    retryable: bool
    detail: str | None = None
