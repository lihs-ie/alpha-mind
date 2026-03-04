"""ModelSnapshot value object."""

import datetime
from dataclasses import dataclass

from signal_generator.domain.enums.model_status import ModelStatus


@dataclass(frozen=True)
class ModelSnapshot:
    """推論に使うモデル情報スナップショット。model_registry の参照コピー。"""

    model_version: str
    status: ModelStatus
    approved_at: datetime.datetime | None
