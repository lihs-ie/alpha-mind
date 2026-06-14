"""ComplianceSnapshot value object."""

from __future__ import annotations

from dataclasses import dataclass

from domain.value_object.enums import InsiderRisk


@dataclass(frozen=True)
class ComplianceSnapshot:
    """Immutable snapshot of compliance state at the time of promotion evaluation.

    Attributes:
        requires_compliance_review: Whether additional compliance review is needed.
        insider_risk: Insider contact risk classification.
        mnpi_self_declared: Whether operator has self-declared no MNPI possession.
    """

    requires_compliance_review: bool
    insider_risk: InsiderRisk
    mnpi_self_declared: bool
