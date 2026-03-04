"""FeatureSnapshot value object."""

import datetime
from dataclasses import dataclass


@dataclass(frozen=True)
class FeatureSnapshot:
    """features.generated の入力スナップショット。RULE-SG-001 の必須項目を保持する。"""

    target_date: datetime.date
    feature_version: str
    storage_path: str
