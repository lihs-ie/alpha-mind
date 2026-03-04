"""SignalGenerationFactory."""

from signal_generator.domain.aggregates.signal_generation import SignalGeneration
from signal_generator.domain.value_objects.feature_snapshot import FeatureSnapshot


class SignalGenerationFactory:
    """features.generated イベントから SignalGeneration 集約を作成するファクトリ。"""

    def from_features_generated_event(
        self,
        identifier: str,
        feature_snapshot: FeatureSnapshot,
        universe_count: int,
        trace: str,
    ) -> SignalGeneration:
        """入力イベントの情報から pending 状態の SignalGeneration を作成する。"""
        return SignalGeneration(
            identifier=identifier,
            feature_snapshot=feature_snapshot,
            universe_count=universe_count,
            trace=trace,
        )
