"""Tests for ValidationRun aggregate."""

import datetime

import pytest

from hypothesis_lab.domain.aggregates.validation_run import ValidationRun
from hypothesis_lab.domain.enums.run_type import RunType
from hypothesis_lab.domain.value_objects.demo_window import DemoWindow
from hypothesis_lab.domain.value_objects.performance_metrics import PerformanceMetrics


def make_executed_at() -> datetime.datetime:
    return datetime.datetime(2026, 3, 1, tzinfo=datetime.timezone.utc)


class TestValidationRunBacktest:
    def test_backtest_run_requires_metrics(self) -> None:
        """INV-HL-004: backtest run_type requires metrics."""
        with pytest.raises(Exception):
            ValidationRun(
                identifier="01HXXXXXXXXXXXXXXXXXXX",
                hypothesis="01HXXXXXXXXXXXXXXXXHYP",
                run_type=RunType.BACKTEST,
                executed_at=make_executed_at(),
                metrics=None,  # Missing metrics — invalid
                demo_window=None,
                promotable=None,
            )

    def test_backtest_run_with_metrics_is_valid(self) -> None:
        """Valid backtest run with metrics succeeds."""
        metrics = PerformanceMetrics(cost_adjusted_return=0.2, dsr=1.5, pbo=0.03)
        validation_run = ValidationRun(
            identifier="01HXXXXXXXXXXXXXXXXXXX",
            hypothesis="01HXXXXXXXXXXXXXXXXHYP",
            run_type=RunType.BACKTEST,
            executed_at=make_executed_at(),
            metrics=metrics,
            demo_window=None,
            promotable=None,
        )
        assert validation_run.metrics == metrics
        assert validation_run.run_type == RunType.BACKTEST


class TestValidationRunDemo:
    def test_demo_run_requires_demo_window(self) -> None:
        """INV-HL-004: demo run_type requires demo_window."""
        with pytest.raises(Exception):
            ValidationRun(
                identifier="01HXXXXXXXXXXXXXXXXXXX",
                hypothesis="01HXXXXXXXXXXXXXXXXHYP",
                run_type=RunType.DEMO,
                executed_at=make_executed_at(),
                metrics=None,
                demo_window=None,  # Missing demo_window — invalid
                promotable=True,
            )

    def test_demo_run_requires_promotable(self) -> None:
        """INV-HL-004: demo run_type requires promotable flag."""
        demo_window = DemoWindow(
            started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.timezone.utc),
            demo_period_days=31,
        )
        with pytest.raises(Exception):
            ValidationRun(
                identifier="01HXXXXXXXXXXXXXXXXXXX",
                hypothesis="01HXXXXXXXXXXXXXXXXHYP",
                run_type=RunType.DEMO,
                executed_at=make_executed_at(),
                metrics=None,
                demo_window=demo_window,
                promotable=None,  # Missing promotable — invalid
            )

    def test_demo_run_with_demo_window_and_promotable_is_valid(self) -> None:
        """Valid demo run with demo_window and promotable succeeds."""
        demo_window = DemoWindow(
            started_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            ended_at=datetime.datetime(2026, 2, 1, tzinfo=datetime.timezone.utc),
            demo_period_days=31,
        )
        validation_run = ValidationRun(
            identifier="01HXXXXXXXXXXXXXXXXXXX",
            hypothesis="01HXXXXXXXXXXXXXXXXHYP",
            run_type=RunType.DEMO,
            executed_at=make_executed_at(),
            metrics=None,
            demo_window=demo_window,
            promotable=True,
        )
        assert validation_run.demo_window == demo_window
        assert validation_run.promotable is True
        assert validation_run.run_type == RunType.DEMO
