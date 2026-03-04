"""Domain service for feature leakage detection."""

import datetime
from dataclasses import dataclass

from domain.specification.point_in_time_consistency import PointInTimeConsistencySpecification
from domain.value_object.enums import ReasonCode
from domain.value_object.insight_snapshot import InsightSnapshot


@dataclass(frozen=True)
class LeakagePolicyResult:
    """Result of feature leakage policy evaluation."""

    leakage_detected: bool
    reason_code: ReasonCode | None


class FeatureLeakagePolicy:
    """Detects future information leakage and determines failure reason code."""

    def evaluate(self, target_date: datetime.date, insight_snapshot: InsightSnapshot) -> LeakagePolicyResult:
        specification = PointInTimeConsistencySpecification(target_date=target_date)

        if not specification.is_satisfied_by(insight_snapshot):
            return LeakagePolicyResult(
                leakage_detected=True,
                reason_code=ReasonCode.DATA_QUALITY_LEAK_DETECTED,
            )

        return LeakagePolicyResult(leakage_detected=False, reason_code=None)
