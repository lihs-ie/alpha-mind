"""ValidationRun entity."""

from __future__ import annotations

import datetime

from domain.value_object.demo_window import DemoWindow
from domain.value_object.enums import RunType
from domain.value_object.performance_metrics import PerformanceMetrics

# Type aliases
ValidationRunIdentifier = str
HypothesisIdentifier = str


class ValidationRun:
    """Entity recording the result of a backtest or demo validation run.

    Enforces invariants:
    - INV-HL-004: runType=backtest requires PerformanceMetrics.
    - INV-HL-004: runType=demo requires DemoWindow and promotable.

    The `hypothesis` field is an identifier reference (HypothesisIdentifier),
    never a direct object reference (INV-HL boundary rule).
    """

    def __init__(
        self,
        identifier: ValidationRunIdentifier,
        hypothesis: HypothesisIdentifier,
        run_type: RunType,
        executed_at: datetime.datetime,
        metrics: PerformanceMetrics | None = None,
        demo_window: DemoWindow | None = None,
        promotable: bool | None = None,
    ) -> None:
        if not identifier:
            raise ValueError("identifier must not be empty")
        if not hypothesis:
            raise ValueError("hypothesis must not be empty")

        # INV-HL-004: backtest requires metrics
        if run_type == RunType.BACKTEST and metrics is None:
            raise ValueError("INV-HL-004: runType=backtest requires PerformanceMetrics (metrics must not be None)")

        # INV-HL-004: demo requires demo_window and promotable
        if run_type == RunType.DEMO:
            if demo_window is None:
                raise ValueError("INV-HL-004: runType=demo requires DemoWindow (demo_window must not be None)")
            if promotable is None:
                raise ValueError("INV-HL-004: runType=demo requires promotable (promotable must not be None)")

        self._identifier = identifier
        self._hypothesis = hypothesis
        self._run_type = run_type
        self._executed_at = executed_at
        self._metrics = metrics
        self._demo_window = demo_window
        self._promotable = promotable

    @property
    def identifier(self) -> ValidationRunIdentifier:
        return self._identifier

    @property
    def hypothesis(self) -> HypothesisIdentifier:
        return self._hypothesis

    @property
    def run_type(self) -> RunType:
        return self._run_type

    @property
    def executed_at(self) -> datetime.datetime:
        return self._executed_at

    @property
    def metrics(self) -> PerformanceMetrics | None:
        return self._metrics

    @property
    def demo_window(self) -> DemoWindow | None:
        return self._demo_window

    @property
    def promotable(self) -> bool | None:
        return self._promotable
