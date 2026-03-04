"""FeaturePayloadIntegritySpecification."""

import datetime
from collections.abc import Callable

from signal_generator.domain.value_objects.feature_snapshot import FeatureSnapshot

_GCS_PREFIX = "gs://"


class FeaturePayloadIntegritySpecification:
    """RULE-SG-001: features.generated 入力必須項目の完全性を検証する仕様。

    targetDate, featureVersion, storagePath の3項目が有効値である場合のみ推論を開始する。
    """

    def __init__(
        self,
        clock: Callable[[], datetime.date] = datetime.date.today,
    ) -> None:
        self._clock = clock

    def is_satisfied_by(self, feature_snapshot: FeatureSnapshot) -> bool:
        if not feature_snapshot.feature_version:
            return False
        if not feature_snapshot.storage_path:
            return False
        if not feature_snapshot.storage_path.startswith(_GCS_PREFIX):
            return False
        # 将来日付は有効な特徴量データとして扱わない（リークリスク防止）
        if feature_snapshot.target_date > self._clock():
            return False
        return True
