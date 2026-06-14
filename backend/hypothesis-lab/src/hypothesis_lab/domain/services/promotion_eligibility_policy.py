"""PromotionEligibilityPolicy domain service."""

from __future__ import annotations

from typing import TYPE_CHECKING

from hypothesis_lab.domain.enums.insider_risk import InsiderRisk
from hypothesis_lab.domain.enums.instrument_type import InstrumentType
from hypothesis_lab.domain.enums.promotion_eligibility import PromotionEligibility
from hypothesis_lab.domain.specifications.promotion_ready_specification import PromotionReadySpecification

if TYPE_CHECKING:
    from hypothesis_lab.domain.aggregates.hypothesis import Hypothesis


class PromotionEligibilityPolicy:
    """RULE-HL-002 / RULE-HL-003: 昇格適格性を判定するドメインポリシー。

    IO 処理を含まず、純粋なドメインロジックのみを担当する。

    自動昇格条件（全条件 AND）:
    1. instrument_type == ETF
    2. insider_risk == LOW
    3. promotable == True
    4. demo_period_days >= 30
    5. requires_compliance_review == False
    6. mnpi_self_declared == True
    7. symbol が partner_restricted_symbols に含まれない

    ブロック条件（何れか 1 つで blocked または eligible_for_manual）:
    - instrument_type == STOCK -> eligible_for_manual
    - insider_risk in {MEDIUM, HIGH} -> blocked
    - mnpi_self_declared == False または未設定 -> blocked
    - symbol in partner_restricted_symbols -> blocked
    - requires_compliance_review == True -> blocked
    - demo_period_days < 30 -> blocked
    """

    def check(
        self, hypothesis: Hypothesis, partner_restricted_symbols: set[str]
    ) -> PromotionEligibility:
        """仮説の昇格適格性を判定する。IO を含まない。"""
        # まず PromotionReadySpecification で基本前提条件を確認
        ready_spec = PromotionReadySpecification()

        # 各ブロック条件を個別にチェック
        # requires_compliance_review=True は blocked
        if hypothesis.requires_compliance_review is True:
            return PromotionEligibility.BLOCKED

        # demo_period_days < 30 は blocked（demo_window が None の場合も blocked）
        if hypothesis.demo_window is None or hypothesis.demo_window.demo_period_days < 30:
            return PromotionEligibility.BLOCKED

        # promotable でない場合は blocked
        if hypothesis.promotable is not True:
            return PromotionEligibility.BLOCKED

        # symbol が partner_restricted_symbols に含まれる場合は blocked
        if hypothesis.symbol in partner_restricted_symbols:
            return PromotionEligibility.BLOCKED

        # mnpi_self_declared が False または未設定の場合は blocked
        if hypothesis.mnpi_self_declared is not True:
            return PromotionEligibility.BLOCKED

        # insider_risk が MEDIUM または HIGH の場合は blocked
        if hypothesis.insider_risk in (InsiderRisk.MEDIUM, InsiderRisk.HIGH):
            return PromotionEligibility.BLOCKED

        # STOCK の場合は eligible_for_manual（自動昇格不可）
        if hypothesis.instrument_type == InstrumentType.STOCK:
            return PromotionEligibility.ELIGIBLE_FOR_MANUAL

        # 全条件を満たした場合は eligible_for_auto (ETF + LOW + すべての条件)
        return PromotionEligibility.ELIGIBLE_FOR_AUTO
