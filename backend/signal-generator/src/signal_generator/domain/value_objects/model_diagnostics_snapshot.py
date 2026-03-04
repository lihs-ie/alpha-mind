"""ModelDiagnosticsSnapshot value object."""

from dataclasses import dataclass

from signal_generator.domain.enums.degradation_flag import DegradationFlag


@dataclass(frozen=True)
class ModelDiagnosticsSnapshot:
    """推論結果に付随するモデル診断情報。

    RULE-SG-006: signal.generated に必須で含める。
    RULE-SG-007: degradationFlag=block のとき requiresComplianceReview=true を強制する。
    """

    degradation_flag: DegradationFlag
    requires_compliance_review: bool
    cost_adjusted_return: float | None = None
    slippage_adjusted_sharpe: float | None = None

    def __post_init__(self) -> None:
        # RULE-SG-007: block フラグ時はコンプライアンスレビューが必須
        if self.degradation_flag.requires_compliance_review() and not self.requires_compliance_review:
            raise ValueError(
                "degradationFlag=block のとき requiresComplianceReview は true でなければならない (RULE-SG-007)"
            )
