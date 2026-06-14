"""PromotionReadySpecification."""

from __future__ import annotations

from typing import TYPE_CHECKING

from hypothesis_lab.domain.enums.hypothesis_status import HypothesisStatus

if TYPE_CHECKING:
    from hypothesis_lab.domain.aggregates.hypothesis import Hypothesis


class PromotionReadySpecification:
    """INV-HL-002: live 遷移の前提条件を検証する仕様。

    True を返す条件（全条件 AND）:
    1. status == DEMO
    2. promotable == True（最新 demo 評価）
    3. demo_period_days >= 30
    4. requires_compliance_review == False
    """

    def is_satisfied_by(self, hypothesis: Hypothesis) -> bool:
        """仮説が昇格前提条件を満たすかどうかを判定する。IO を含まない。"""
        if hypothesis.status != HypothesisStatus.DEMO:
            return False
        if hypothesis.demo_window is None:
            return False
        if hypothesis.promotable is not True:
            return False
        if hypothesis.demo_window.demo_period_days < 30:
            return False
        if hypothesis.requires_compliance_review is not False:
            return False
        return True
