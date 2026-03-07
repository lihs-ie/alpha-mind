"""ModelSnapshot value object."""

import datetime
from dataclasses import dataclass, field

from signal_generator.domain.enums.degradation_flag import DegradationFlag
from signal_generator.domain.enums.model_status import ModelStatus


@dataclass(frozen=True)
class ModelSnapshot:
    """推論に使うモデル情報スナップショット。model_registry の参照コピー。"""

    model_version: str
    status: ModelStatus
    approved_at: datetime.datetime | None
    degradation_flag: DegradationFlag = field(default=DegradationFlag.NORMAL)
    cost_adjusted_return: float | None = field(default=None)
    slippage_adjusted_sharpe: float | None = field(default=None)

    @property
    def requires_compliance_review(self) -> bool:
        """RULE-SG-007: degradation_flag から導出する。"""
        return self.degradation_flag.requires_compliance_review()
