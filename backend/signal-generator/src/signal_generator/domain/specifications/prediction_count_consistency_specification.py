"""PredictionCountConsistencySpecification."""

from signal_generator.domain.value_objects.signal_artifact import SignalArtifact


class PredictionCountConsistencySpecification:
    """RULE-SG-004: 推論件数とユニバース件数の一致を検証する仕様。

    SignalArtifact の不変条件として既に検証済みだが、
    明示的な仕様オブジェクトとして公開することで業務ルールのトレーサビリティを確保する。
    """

    def is_satisfied_by(self, signal_artifact: SignalArtifact) -> bool:
        return signal_artifact.generated_count == signal_artifact.universe_count
