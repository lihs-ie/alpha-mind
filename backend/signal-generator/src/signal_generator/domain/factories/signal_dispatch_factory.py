"""SignalDispatchFactory."""

from signal_generator.domain.aggregates.signal_dispatch import SignalDispatch


class SignalDispatchFactory:
    """SignalGeneration の識別情報から SignalDispatch 集約を作成するファクトリ。

    SignalDispatch は SignalGeneration と同じ identifier を使い、
    冪等性キーとして idempotency_keys コレクションに記録する。
    集約間参照はID参照のみとし、オブジェクト参照を禁止する。
    """

    def from_signal_generation(self, identifier: str, trace: str) -> SignalDispatch:
        """SignalGeneration の識別情報から pending 状態の SignalDispatch を作成する。"""
        return SignalDispatch(
            identifier=identifier,
            trace=trace,
        )
