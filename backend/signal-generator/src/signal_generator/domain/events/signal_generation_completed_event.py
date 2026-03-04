"""SignalGenerationCompletedEvent domain event."""

import datetime
from dataclasses import dataclass

from signal_generator.domain.enums.event_type import EventType
from signal_generator.domain.value_objects.model_diagnostics_snapshot import ModelDiagnosticsSnapshot


@dataclass(frozen=True)
class SignalGenerationCompletedEvent:
    """signal.generation.completed: 生成確定時に発行する境界内ドメインイベント。

    RULE-SG-006: modelDiagnostics は必須。
    """

    identifier: str
    signal_version: str
    model_version: str
    feature_version: str
    storage_path: str
    model_diagnostics_snapshot: ModelDiagnosticsSnapshot
    trace: str
    occurred_at: datetime.datetime
    event_type: EventType = EventType.SIGNAL_GENERATION_COMPLETED
