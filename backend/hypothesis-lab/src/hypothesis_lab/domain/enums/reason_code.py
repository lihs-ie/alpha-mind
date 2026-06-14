"""ReasonCode enumeration for failure knowledge."""

from enum import StrEnum


class ReasonCode(StrEnum):
    """失敗理由コード。"""

    REQUEST_VALIDATION_FAILED = "request_validation_failed"
    STATE_CONFLICT = "state_conflict"
    OPERATION_NOT_ALLOWED = "operation_not_allowed"
    COMPLIANCE_REVIEW_REQUIRED = "compliance_review_required"
    COMPLIANCE_MNPI_SUSPECTED = "compliance_mnpi_suspected"
    COMPLIANCE_RESTRICTED_SYMBOL = "compliance_restricted_symbol"
    BACKTEST_FAILED = "backtest_failed"
    DEMO_PERIOD_INSUFFICIENT = "demo_period_insufficient"
