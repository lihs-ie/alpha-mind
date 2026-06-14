"""HypothesisPromotedEvent domain event type definition."""

import datetime
from dataclasses import dataclass

from hypothesis_lab.domain.enums.decision_result import DecisionResult
from hypothesis_lab.domain.enums.insider_risk import InsiderRisk
from hypothesis_lab.domain.enums.operator_action_reason_code import OperatorActionReasonCode
from hypothesis_lab.domain.enums.promotion_mode import PromotionMode
from hypothesis_lab.domain.identifiers import HypothesisIdentifier


@dataclass(frozen=True)
class HypothesisPromotedEvent:
    """hypothesis.promoted ドメインイベント型定義。

    M-12: イベント発行（Pub/Sub 送信）は application 層の責務。domain 層は型定義のみを持つ。
    """

    identifier: HypothesisIdentifier
    hypothesis: HypothesisIdentifier
    decision: DecisionResult
    action_reason_code: OperatorActionReasonCode
    promotion_mode: PromotionMode
    mnpi_self_declared: bool
    insider_risk: InsiderRisk
    occurred_at: datetime.datetime
    trace: str
