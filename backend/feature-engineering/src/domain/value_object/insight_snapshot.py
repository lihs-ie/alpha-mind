"""InsightSnapshot value object - qualitative insight summary filtered by target date."""

import datetime
from dataclasses import dataclass


@dataclass(frozen=True)
class InsightSnapshot:
    """Summary of insight records filtered by target date for point-in-time consistency."""

    record_count: int
    latest_collected_at: datetime.datetime | None
    filtered_by_target_date: bool

    def __post_init__(self) -> None:
        if self.record_count < 0:
            raise ValueError(f"record_count must be non-negative, got {self.record_count}")
        if self.latest_collected_at is not None and self.latest_collected_at.tzinfo is None:
            raise ValueError("latest_collected_at must be timezone-aware (UTC expected)")
