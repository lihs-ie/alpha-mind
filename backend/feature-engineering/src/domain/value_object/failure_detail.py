"""FailureDetail value object - failure information with reason code."""

from dataclasses import dataclass

from domain.value_object.enums import ReasonCode


@dataclass(frozen=True)
class FailureDetail:
    """Detailed failure information including reason code and retryability."""

    reason_code: ReasonCode
    detail: str | None
    retryable: bool
