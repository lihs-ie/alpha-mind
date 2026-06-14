"""ComplianceSnapshot value object."""

from dataclasses import dataclass

from hypothesis_lab.domain.enums.insider_risk import InsiderRisk


@dataclass(frozen=True)
class ComplianceSnapshot:
    """昇格判定時のコンプライアンス状態スナップショット。

    INV: 全フィールド必須。Value Object として値比較で等価判定し、immutable。
    """

    requires_compliance_review: bool
    insider_risk: InsiderRisk
    mnpi_self_declared: bool
