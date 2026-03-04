"""InferenceConsistencyPolicy domain service."""

from signal_generator.domain.value_objects.model_diagnostics_snapshot import ModelDiagnosticsSnapshot
from signal_generator.domain.value_objects.signal_artifact import SignalArtifact


class InferenceConsistencyPolicy:
    """推論件数整合と診断情報補正を担当するドメインポリシー。

    RULE-SG-004: 推論件数とユニバース件数の一致を検証する。
    RULE-SG-007: block フラグ時の requiresComplianceReview=true を保証する。
    IO処理を含まない純粋なドメインロジックのみを担当する。
    """

    def is_satisfied_by(self, signal_artifact: SignalArtifact) -> bool:
        """RULE-SG-004: 推論件数とユニバース件数が一致しているか検証する。

        SignalArtifact のコンストラクタで既に一致検証を行うため、
        インスタンスが存在すれば常に True を返す。
        """
        return signal_artifact.generated_count == signal_artifact.universe_count

    def apply_compliance_review_rule(
        self, model_diagnostics_snapshot: ModelDiagnosticsSnapshot
    ) -> ModelDiagnosticsSnapshot:
        """RULE-SG-007: degradationFlag=block のとき requiresComplianceReview=true を強制する。

        不変な値オブジェクトなので補正が必要な場合は新しいインスタンスを返す。
        """
        if model_diagnostics_snapshot.degradation_flag.requires_compliance_review():
            return ModelDiagnosticsSnapshot(
                degradation_flag=model_diagnostics_snapshot.degradation_flag,
                requires_compliance_review=True,
                cost_adjusted_return=model_diagnostics_snapshot.cost_adjusted_return,
                slippage_adjusted_sharpe=model_diagnostics_snapshot.slippage_adjusted_sharpe,
            )
        return model_diagnostics_snapshot
