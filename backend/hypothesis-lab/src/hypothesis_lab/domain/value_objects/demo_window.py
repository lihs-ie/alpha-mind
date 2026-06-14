"""DemoWindow value object."""

import datetime
from dataclasses import dataclass


@dataclass(frozen=True)
class DemoWindow:
    """demo 期間情報。

    INV: 全フィールド必須。Value Object として値比較で等価判定し、immutable。
    """

    started_at: datetime.datetime
    ended_at: datetime.datetime
    demo_period_days: int
