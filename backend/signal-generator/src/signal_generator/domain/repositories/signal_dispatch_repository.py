"""SignalDispatchRepository interface."""

import abc

from signal_generator.domain.aggregates.signal_dispatch import SignalDispatch


class SignalDispatchRepository(abc.ABC):
    """SignalDispatch 集約の永続化インターフェース。idempotency_keys コレクション対応。"""

    @abc.abstractmethod
    def find(self, identifier: str) -> SignalDispatch | None:
        """identifier を指定して SignalDispatch を単体取得する。"""

    @abc.abstractmethod
    def persist(self, signal_dispatch: SignalDispatch) -> None:
        """SignalDispatch を永続化する。"""

    @abc.abstractmethod
    def terminate(self, identifier: str) -> None:
        """identifier を指定して SignalDispatch を削除する。"""
