"""Tests for hypothesis-lab enum value objects (Must-V-01, Must-V-02)."""

from __future__ import annotations

import datetime

import pytest

from domain.value_object.compliance_snapshot import ComplianceSnapshot
from domain.value_object.demo_window import DemoWindow
from domain.value_object.enums import (
    HypothesisStatus,
    InsiderRisk,
    InstrumentType,
    PromotionDecisionType,
    PromotionMode,
    ReasonCode,
    RunType,
)
from domain.value_object.failure_summary import FailureSummary
from domain.value_object.performance_metrics import PerformanceMetrics
from domain.value_object.promotion_decision import PromotionDecision


class TestHypothesisStatus:
    def test_all_values_defined(self) -> None:
        assert HypothesisStatus.DRAFT.value == "draft"
        assert HypothesisStatus.BACKTESTED.value == "backtested"
        assert HypothesisStatus.DEMO.value == "demo"
        assert HypothesisStatus.LIVE.value == "live"
        assert HypothesisStatus.REJECTED.value == "rejected"

    def test_enum_members_are_five(self) -> None:
        assert len(HypothesisStatus) == 5


class TestInstrumentType:
    def test_etf_and_stock_defined(self) -> None:
        assert InstrumentType.ETF.value == "ETF"
        assert InstrumentType.STOCK.value == "STOCK"


class TestInsiderRisk:
    def test_levels_defined(self) -> None:
        assert InsiderRisk.LOW.value == "low"
        assert InsiderRisk.MEDIUM.value == "medium"
        assert InsiderRisk.HIGH.value == "high"


class TestPromotionMode:
    def test_modes_defined(self) -> None:
        assert PromotionMode.MANUAL.value == "manual"
        assert PromotionMode.AUTO.value == "auto"


class TestRunType:
    def test_run_types_defined(self) -> None:
        assert RunType.BACKTEST.value == "backtest"
        assert RunType.DEMO.value == "demo"


class TestReasonCode:
    def test_all_codes_defined(self) -> None:
        assert ReasonCode.REQUEST_VALIDATION_FAILED.value == "REQUEST_VALIDATION_FAILED"
        assert ReasonCode.OPERATION_NOT_ALLOWED.value == "OPERATION_NOT_ALLOWED"
        assert ReasonCode.COMPLIANCE_REVIEW_REQUIRED.value == "COMPLIANCE_REVIEW_REQUIRED"
        assert ReasonCode.STATE_CONFLICT.value == "STATE_CONFLICT"
        assert ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT.value == "IDEMPOTENCY_DUPLICATE_EVENT"


class TestPerformanceMetrics:
    def test_immutable_value_object(self) -> None:
        metrics = PerformanceMetrics(cost_adjusted_return=0.15, dsr=1.2, pbo=0.1)
        with pytest.raises((AttributeError, TypeError)):
            metrics.cost_adjusted_return = 0.99  # type: ignore[misc]

    def test_value_equality(self) -> None:
        metrics_a = PerformanceMetrics(cost_adjusted_return=0.15, dsr=1.2, pbo=0.1)
        metrics_b = PerformanceMetrics(cost_adjusted_return=0.15, dsr=1.2, pbo=0.1)
        assert metrics_a == metrics_b

    def test_value_inequality(self) -> None:
        metrics_a = PerformanceMetrics(cost_adjusted_return=0.15, dsr=1.2, pbo=0.1)
        metrics_b = PerformanceMetrics(cost_adjusted_return=0.99, dsr=1.2, pbo=0.1)
        assert metrics_a != metrics_b


class TestDemoWindow:
    def test_immutable_value_object(self) -> None:
        window = DemoWindow(
            started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
            ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.UTC),
            demo_period_days=31,
        )
        with pytest.raises((AttributeError, TypeError)):
            window.demo_period_days = 99  # type: ignore[misc]

    def test_value_equality(self) -> None:
        started_at = datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC)
        ended_at = datetime.datetime(2026, 2, 1, tzinfo=datetime.UTC)
        window_a = DemoWindow(started_at=started_at, ended_at=ended_at, demo_period_days=31)
        window_b = DemoWindow(started_at=started_at, ended_at=ended_at, demo_period_days=31)
        assert window_a == window_b


class TestComplianceSnapshot:
    def test_immutable_value_object(self) -> None:
        snapshot = ComplianceSnapshot(
            requires_compliance_review=False,
            insider_risk=InsiderRisk.LOW,
            mnpi_self_declared=True,
        )
        with pytest.raises((AttributeError, TypeError)):
            snapshot.requires_compliance_review = True  # type: ignore[misc]

    def test_value_equality(self) -> None:
        snapshot_a = ComplianceSnapshot(
            requires_compliance_review=False,
            insider_risk=InsiderRisk.LOW,
            mnpi_self_declared=True,
        )
        snapshot_b = ComplianceSnapshot(
            requires_compliance_review=False,
            insider_risk=InsiderRisk.LOW,
            mnpi_self_declared=True,
        )
        assert snapshot_a == snapshot_b


class TestPromotionDecision:
    def test_immutable_value_object(self) -> None:
        decision = PromotionDecision(
            decision=PromotionDecisionType.PROMOTED,
            action_reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            promotion_mode=PromotionMode.MANUAL,
        )
        with pytest.raises((AttributeError, TypeError)):
            decision.decision = PromotionDecisionType.REJECTED  # type: ignore[misc]

    def test_value_equality(self) -> None:
        decision_a = PromotionDecision(
            decision=PromotionDecisionType.PROMOTED,
            action_reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            promotion_mode=PromotionMode.MANUAL,
        )
        decision_b = PromotionDecision(
            decision=PromotionDecisionType.PROMOTED,
            action_reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            promotion_mode=PromotionMode.MANUAL,
        )
        assert decision_a == decision_b


class TestFailureSummary:
    def test_immutable_value_object(self) -> None:
        summary = FailureSummary(
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            markdown_summary="## Failure\nTest failed.",
        )
        with pytest.raises((AttributeError, TypeError)):
            summary.markdown_summary = "changed"  # type: ignore[misc]

    def test_value_equality(self) -> None:
        summary_a = FailureSummary(
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            markdown_summary="## Failure\nTest failed.",
        )
        summary_b = FailureSummary(
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            markdown_summary="## Failure\nTest failed.",
        )
        assert summary_a == summary_b

    def test_rejects_empty_markdown_summary(self) -> None:
        with pytest.raises(ValueError, match="markdown_summary must not be empty"):
            FailureSummary(
                reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
                markdown_summary="",
            )
