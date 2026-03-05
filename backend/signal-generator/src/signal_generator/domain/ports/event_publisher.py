"""SignalEventPublisher port."""

import abc

from signal_generator.domain.events.signal_generation_completed_event import (
    SignalGenerationCompletedEvent,
)
from signal_generator.domain.events.signal_generation_failed_event import (
    SignalGenerationFailedEvent,
)


class SignalEventPublisher(abc.ABC):
    """シグナルイベントを外部イベントバスに発行するポート。"""

    @abc.abstractmethod
    def publish_signal_generated(self, event: SignalGenerationCompletedEvent) -> str:
        """signal.generated イベントを発行し、メッセージ ID を返す。"""

    @abc.abstractmethod
    def publish_signal_generation_failed(self, event: SignalGenerationFailedEvent) -> str:
        """signal.generation.failed イベントを発行し、メッセージ ID を返す。"""
