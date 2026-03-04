"""SignalGenerationRepository interface."""

import abc

from signal_generator.domain.aggregates.signal_generation import SignalGeneration
from signal_generator.domain.enums.generation_status import GenerationStatus


class SignalGenerationRepository(abc.ABC):
    """SignalGeneration 集約の永続化インターフェース。"""

    @abc.abstractmethod
    def find(self, identifier: str) -> SignalGeneration | None:
        """identifier を指定して SignalGeneration を単体取得する。"""

    @abc.abstractmethod
    def find_by_status(self, status: GenerationStatus) -> list[SignalGeneration]:
        """status を指定して SignalGeneration を取得する。"""

    @abc.abstractmethod
    def search(self, criteria: dict[str, object]) -> list[SignalGeneration]:
        """検索条件を受け取り条件に合致する SignalGeneration を全て取得する。"""

    @abc.abstractmethod
    def persist(self, signal_generation: SignalGeneration) -> None:
        """SignalGeneration を永続化する。"""

    @abc.abstractmethod
    def terminate(self, identifier: str) -> None:
        """identifier を指定して SignalGeneration を削除する。"""
