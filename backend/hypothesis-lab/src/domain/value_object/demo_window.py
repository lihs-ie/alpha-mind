"""DemoWindow value object."""

from __future__ import annotations

import datetime
from dataclasses import dataclass


@dataclass(frozen=True)
class DemoWindow:
    """Immutable value object representing the demo run period.

    Attributes:
        started_at: Demo period start datetime (UTC).
        ended_at: Demo period end datetime (UTC).
        demo_period_days: Number of calendar days in the demo period.
    """

    started_at: datetime.datetime
    ended_at: datetime.datetime
    demo_period_days: int
