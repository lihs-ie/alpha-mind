"""RunType enumeration."""

from enum import StrEnum


class RunType(StrEnum):
    """検証実行種別。"""

    BACKTEST = "backtest"
    DEMO = "demo"
