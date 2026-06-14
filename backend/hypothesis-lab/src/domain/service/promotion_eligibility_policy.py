"""PromotionEligibilityPolicy domain service."""

from __future__ import annotations

from typing import TYPE_CHECKING

from domain.value_object.enums import InsiderRisk, InstrumentType

if TYPE_CHECKING:
    from domain.model.hypothesis import Hypothesis


class PromotionEligibilityPolicy:
    """Pure domain service for evaluating auto-promotion eligibility.

    Must-DS-01: no IO, pure function over Hypothesis state.

    Implements RULE-HL-002 and RULE-HL-003 as a single composable check.
    All 7 conditions must be satisfied for auto-promotion to be eligible.
    """

    def check_auto_eligibility(
        self,
        hypothesis: Hypothesis,
        partner_restricted_symbols: list[str],
    ) -> bool:
        """Return True iff the hypothesis satisfies all auto-promotion conditions.

        Conditions (Must-S-02):
        1. auto_promotion_eligible=true or (promotable is implied by demo_window context)
           - We check the demo_window.demo_period_days >= 30
        2. demo_window.demo_period_days >= 30
        3. requires_compliance_review=false (None counts as false)
        4. instrument_type=ETF
        5. insider_risk=low
        6. mnpi_self_declared=true
        7. symbol not in partner_restricted_symbols

        Args:
            hypothesis: The Hypothesis aggregate to evaluate.
            partner_restricted_symbols: List of symbol strings that are restricted.

        Returns:
            True if all 7 conditions are met, False otherwise.
        """
        demo_window = hypothesis.demo_window
        if demo_window is None:
            return False

        if demo_window.demo_period_days < 30:
            return False

        if hypothesis.requires_compliance_review:
            return False

        if hypothesis.instrument_type != InstrumentType.ETF:
            return False

        if hypothesis.insider_risk != InsiderRisk.LOW:
            return False

        if not hypothesis.mnpi_self_declared:
            return False

        return hypothesis.symbol not in partner_restricted_symbols
