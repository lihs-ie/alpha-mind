"""PerformanceMetrics value object."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class PerformanceMetrics:
    """Immutable value object holding statistical performance indicators.

    Attributes:
        cost_adjusted_return: Return adjusted for transaction costs.
        dsr: Deflated Sharpe Ratio.
        pbo: Probability of Backtest Overfitting.
    """

    cost_adjusted_return: float
    dsr: float
    pbo: float
