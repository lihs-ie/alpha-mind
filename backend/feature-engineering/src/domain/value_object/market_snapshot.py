"""MarketSnapshot value object - normalized input from market.collected event."""

import datetime
from dataclasses import dataclass

from domain.value_object.source_status import SourceStatus


@dataclass(frozen=True)
class MarketSnapshot:
    """Normalized summary of a market.collected event payload."""

    target_date: datetime.date
    storage_path: str
    source_status: SourceStatus
