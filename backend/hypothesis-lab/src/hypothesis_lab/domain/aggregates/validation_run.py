"""ValidationRun aggregate."""

import datetime

from hypothesis_lab.domain.enums.run_type import RunType
from hypothesis_lab.domain.exceptions import InvariantViolationError
from hypothesis_lab.domain.identifiers import HypothesisIdentifier, ValidationRunIdentifier
from hypothesis_lab.domain.value_objects.demo_window import DemoWindow
from hypothesis_lab.domain.value_objects.performance_metrics import PerformanceMetrics


class ValidationRun:
    """検証実行結果を保持する独立した集約ルート。

    INV-HL-004:
      - run_type=backtest の場合、metrics は必須。
      - run_type=demo の場合、demo_window と promotable は必須。
    """

    def __init__(
        self,
        identifier: ValidationRunIdentifier,
        hypothesis: HypothesisIdentifier,
        run_type: RunType,
        executed_at: datetime.datetime,
        metrics: PerformanceMetrics | None,
        demo_window: DemoWindow | None,
        promotable: bool | None,
    ) -> None:
        # INV-HL-004: 条件付き必須フィールドの検証
        if run_type == RunType.BACKTEST and metrics is None:
            raise InvariantViolationError(
                "run_type=backtest の場合、metrics は必須です (INV-HL-004)"
            )
        if run_type == RunType.DEMO:
            if demo_window is None:
                raise InvariantViolationError(
                    "run_type=demo の場合、demo_window は必須です (INV-HL-004)"
                )
            if promotable is None:
                raise InvariantViolationError(
                    "run_type=demo の場合、promotable は必須です (INV-HL-004)"
                )

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
