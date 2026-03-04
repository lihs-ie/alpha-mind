"""SignalDispatchFactory."""

from signal_generator.domain.aggregates.signal_dispatch import SignalDispatch
from signal_generator.domain.aggregates.signal_generation import SignalGeneration


class SignalDispatchFactory:
    """SignalGeneration から SignalDispatch 集約を作成するファクトリ。

    SignalDispatch は SignalGeneration と同じ identifier を使い、
    冪等性キーとして idempotency_keys コレクションに記録する。
    """

    def from_signal_generation(self, signal_generation: SignalGeneration) -> SignalDispatch:
        """SignalGeneration の情報から pending 状態の SignalDispatch を作成する。"""
        return SignalDispatch(
            identifier=signal_generation.identifier,
            trace=signal_generation.trace,
        )
