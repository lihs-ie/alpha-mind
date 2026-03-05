"""InferenceConsistencyPolicy domain service."""

from signal_generator.domain.value_objects.model_diagnostics_snapshot import ModelDiagnosticsSnapshot


class InferenceConsistencyPolicy:
    """推論件数整合と診断情報検証を担当するドメインポリシー。

    RULE-SG-004: 推論件数とユニバース件数の一致を検証する。
    RULE-SG-007: block フラグ時の requiresComplianceReview=true を検証する。
    IO処理を含まない純粋なドメインロジックのみを担当する。
    """

    def is_count_consistent(self, generated_count: int, universe_count: int) -> bool:
        """RULE-SG-004: 推論件数とユニバース件数が一致しているか検証する。"""
        return generated_count == universe_count

    def is_compliance_review_satisfied(self, model_diagnostics: ModelDiagnosticsSnapshot) -> bool:
        """RULE-SG-007: degradationFlag=block のとき requiresComplianceReview=true であることを検証する。

        ModelDiagnosticsSnapshot の __post_init__ で不変条件として既に強制されるため、
        インスタンスが存在する時点で常に True を返す。
        アプリケーション層からの明示的な検証ポイントとして提供する。
        """
        if model_diagnostics.degradation_flag.requires_compliance_review():
            return model_diagnostics.requires_compliance_review
        return True
