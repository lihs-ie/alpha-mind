"""PerformanceMetrics value object."""

from dataclasses import dataclass


@dataclass(frozen=True)
class PerformanceMetrics:
    """仮説の成績指標。

    INV: 全フィールド必須。Value Object として値比較で等価判定し、immutable。
    """

    cost_adjusted_return: float
    dsr: float
    pbo: float
