"""Specification for RULE-FE-003 / INV-FE-003: point-in-time consistency check."""

import datetime

from domain.value_object.insight_snapshot import InsightSnapshot


class PointInTimeConsistencySpecification:
    """Validates that insight records do not contain future information relative to target_date.

    INV-FE-003: insight.latestCollectedAt <= targetDate (end of day).
    Also requires that the snapshot has been filtered by target_date.
    """

    def __init__(self, target_date: datetime.date) -> None:
        self._target_date = target_date

    def is_satisfied_by(self, snapshot: InsightSnapshot) -> bool:
        if not snapshot.filtered_by_target_date:
            return False

        if snapshot.latest_collected_at is None:
            # record_count > 0 なのに収集時刻が不明な場合は安全と見なせない
            return snapshot.record_count == 0

        # target_date の終わり (翌日 00:00:00 UTC) より前であること
        target_date_end = datetime.datetime(
            self._target_date.year,
            self._target_date.month,
            self._target_date.day,
            tzinfo=datetime.UTC,
        ) + datetime.timedelta(days=1)

        return snapshot.latest_collected_at < target_date_end
