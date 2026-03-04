"""Domain service for point-in-time join consistency validation."""

import datetime
from dataclasses import dataclass

from domain.specification.point_in_time_consistency import PointInTimeConsistencySpecification
from domain.value_object.insight_snapshot import InsightSnapshot


@dataclass(frozen=True)
class JoinPolicyResult:
    """Result of point-in-time join policy evaluation."""

    approved: bool
    reason: str | None


class PointInTimeJoinPolicy:
    """Determines whether quantitative/qualitative data join is temporally consistent."""

    def evaluate(self, target_date: datetime.date, insight_snapshot: InsightSnapshot) -> JoinPolicyResult:
        specification = PointInTimeConsistencySpecification(target_date=target_date)

        if not specification.is_satisfied_by(insight_snapshot):
            if not insight_snapshot.filtered_by_target_date:
                return JoinPolicyResult(approved=False, reason="Insight snapshot was not filtered by target_date")
            return JoinPolicyResult(
                approved=False,
                reason=f"latest_collected_at ({insight_snapshot.latest_collected_at}) exceeds target_date ({target_date})",
            )

        return JoinPolicyResult(approved=True, reason=None)
