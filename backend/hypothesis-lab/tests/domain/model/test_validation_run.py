"""Tests for ValidationRun entity (Must-E-04, Must-E-05, Must-E-06)."""

from __future__ import annotations

import datetime

import pytest

from domain.model.validation_run import ValidationRun
from domain.value_object.demo_window import DemoWindow
from domain.value_object.enums import RunType
from domain.value_object.performance_metrics import PerformanceMetrics

_NOW = datetime.datetime(2026, 3, 1, tzinfo=datetime.UTC)


def _make_metrics() -> PerformanceMetrics:
    return PerformanceMetrics(cost_adjusted_return=0.12, dsr=1.5, pbo=0.05)


def _make_demo_window(demo_period_days: int = 30) -> DemoWindow:
    return DemoWindow(
        started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.UTC),
        demo_period_days=demo_period_days,
    )


class TestValidationRunCreation:
    """Must-E-04: Required fields present, hypothesis is identifier reference."""

    def test_backtest_run_with_required_fields(self) -> None:
        run = ValidationRun(
            identifier="01JNPQRS000000000000000030",
            hypothesis="01JNPQRS000000000000000010",
            run_type=RunType.BACKTEST,
            executed_at=_NOW,
            metrics=_make_metrics(),
        )
        assert run.identifier == "01JNPQRS000000000000000030"
        assert run.hypothesis == "01JNPQRS000000000000000010"
        assert run.run_type == RunType.BACKTEST
        assert run.executed_at == _NOW
        assert run.metrics is not None

    def test_demo_run_with_required_fields(self) -> None:
        run = ValidationRun(
            identifier="01JNPQRS000000000000000031",
            hypothesis="01JNPQRS000000000000000010",
            run_type=RunType.DEMO,
            executed_at=_NOW,
            demo_window=_make_demo_window(),
            promotable=True,
        )
        assert run.run_type == RunType.DEMO
        assert run.demo_window is not None
        assert run.promotable is True

    def test_hypothesis_field_is_string_identifier(self) -> None:
        """Must-E-04: hypothesis is a HypothesisIdentifier (str), not an object reference."""
        run = ValidationRun(
            identifier="01JNPQRS000000000000000030",
            hypothesis="01JNPQRS000000000000000010",
            run_type=RunType.BACKTEST,
            executed_at=_NOW,
            metrics=_make_metrics(),
        )
        assert isinstance(run.hypothesis, str)

    def test_rejects_empty_identifier(self) -> None:
        with pytest.raises(ValueError):
            ValidationRun(
                identifier="",
                hypothesis="01JNPQRS000000000000000010",
                run_type=RunType.BACKTEST,
                executed_at=_NOW,
                metrics=_make_metrics(),
            )

    def test_rejects_empty_hypothesis(self) -> None:
        with pytest.raises(ValueError):
            ValidationRun(
                identifier="01JNPQRS000000000000000030",
                hypothesis="",
                run_type=RunType.BACKTEST,
                executed_at=_NOW,
                metrics=_make_metrics(),
            )


class TestValidationRunBacktestInvariant:
    """Must-E-05: INV-HL-004 — backtest requires PerformanceMetrics."""

    def test_backtest_without_metrics_raises_error(self) -> None:
        """TST-HL-010: runType=backtest without metrics is rejected."""
        with pytest.raises(ValueError, match="INV-HL-004"):
            ValidationRun(
                identifier="01JNPQRS000000000000000030",
                hypothesis="01JNPQRS000000000000000010",
                run_type=RunType.BACKTEST,
                executed_at=_NOW,
                metrics=None,
            )

    def test_backtest_with_metrics_succeeds(self) -> None:
        run = ValidationRun(
            identifier="01JNPQRS000000000000000030",
            hypothesis="01JNPQRS000000000000000010",
            run_type=RunType.BACKTEST,
            executed_at=_NOW,
            metrics=_make_metrics(),
        )
        assert run.metrics is not None


class TestValidationRunDemoInvariant:
    """Must-E-06: INV-HL-004 — demo requires DemoWindow and promotable."""

    def test_demo_without_demo_window_raises_error(self) -> None:
        with pytest.raises(ValueError, match="INV-HL-004"):
            ValidationRun(
                identifier="01JNPQRS000000000000000031",
                hypothesis="01JNPQRS000000000000000010",
                run_type=RunType.DEMO,
                executed_at=_NOW,
                demo_window=None,
                promotable=True,
            )

    def test_demo_without_promotable_raises_error(self) -> None:
        with pytest.raises(ValueError, match="INV-HL-004"):
            ValidationRun(
                identifier="01JNPQRS000000000000000031",
                hypothesis="01JNPQRS000000000000000010",
                run_type=RunType.DEMO,
                executed_at=_NOW,
                demo_window=_make_demo_window(),
                promotable=None,
            )

    def test_demo_with_all_required_fields_succeeds(self) -> None:
        run = ValidationRun(
            identifier="01JNPQRS000000000000000031",
            hypothesis="01JNPQRS000000000000000010",
            run_type=RunType.DEMO,
            executed_at=_NOW,
            demo_window=_make_demo_window(),
            promotable=True,
        )
        assert run.demo_window is not None
        assert run.promotable is True
