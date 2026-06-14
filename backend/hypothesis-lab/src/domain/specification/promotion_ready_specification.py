"""PromotionReadySpecification — checks promotion candidate conditions."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from domain.model.hypothesis import Hypothesis


class PromotionReadySpecification:
    """Specification for RULE-HL-002 promotion candidate conditions.

    Must-SP-01: is_satisfied_by checks promotable=true AND demoPeriodDays>=30
    AND requiresComplianceReview=false.

    Note: This specification checks the base promotion readiness conditions
    (RULE-HL-002). Additional auto-promotion conditions (RULE-HL-003) are
    checked separately by PromotionEligibilityPolicy.
    """

    def is_satisfied_by(self, hypothesis: Hypothesis) -> bool:
        """Return True iff hypothesis satisfies basic promotion readiness (RULE-HL-002).

        Conditions:
        - auto_promotion_eligible=true (the hypothesis has been flagged as promotable
          by a completed demo run)
        - demo_window.demo_period_days >= 30
        - requires_compliance_review=false (None counts as not required)

        Args:
            hypothesis: Hypothesis aggregate to evaluate.

        Returns:
            True if all three conditions are satisfied, False otherwise.
        """
        if not hypothesis.auto_promotion_eligible:
            return False

        demo_window = hypothesis.demo_window
        if demo_window is None:
            return False

        if demo_window.demo_period_days < 30:
            return False

        return not hypothesis.requires_compliance_review
