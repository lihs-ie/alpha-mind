"""Domain enum types for the hypothesis-lab bounded context."""

from __future__ import annotations

from enum import Enum


class HypothesisStatus(Enum):
    """Lifecycle status of a hypothesis."""

    DRAFT = "draft"
    BACKTESTED = "backtested"
    DEMO = "demo"
    LIVE = "live"
    REJECTED = "rejected"


class InstrumentType(Enum):
    """Financial instrument type."""

    ETF = "ETF"
    STOCK = "STOCK"


class InsiderRisk(Enum):
    """Insider contact risk level."""

    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class PromotionMode(Enum):
    """Mode by which a hypothesis was promoted."""

    MANUAL = "manual"
    AUTO = "auto"


class RunType(Enum):
    """Validation run type."""

    BACKTEST = "backtest"
    DEMO = "demo"


class PromotionDecisionType(Enum):
    """Result of a promotion decision."""

    PROMOTED = "promoted"
    REJECTED = "rejected"


class ReasonCode(Enum):
    """Reason codes for failures and operation errors in hypothesis-lab."""

    REQUEST_VALIDATION_FAILED = "REQUEST_VALIDATION_FAILED"
    OPERATION_NOT_ALLOWED = "OPERATION_NOT_ALLOWED"
    COMPLIANCE_REVIEW_REQUIRED = "COMPLIANCE_REVIEW_REQUIRED"
    STATE_CONFLICT = "STATE_CONFLICT"
    IDEMPOTENCY_DUPLICATE_EVENT = "IDEMPOTENCY_DUPLICATE_EVENT"
