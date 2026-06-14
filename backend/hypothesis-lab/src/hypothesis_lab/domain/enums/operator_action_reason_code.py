"""OperatorActionReasonCode enumeration."""

from enum import StrEnum


class OperatorActionReasonCode(StrEnum):
    """オペレーターアクション理由コード。"""

    BACKTEST_PASSED = "backtest_passed"
    DEMO_COMPLETED_AUTO = "demo_completed_auto"
    DEMO_COMPLETED_MANUAL = "demo_completed_manual"
    COMPLIANCE_REJECTED = "compliance_rejected"
    PERFORMANCE_REJECTED = "performance_rejected"
