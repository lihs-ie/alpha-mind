"""HypothesisDemoCompletedEvent domain event type definition."""

import datetime
from dataclasses import dataclass

from hypothesis_lab.domain.identifiers import HypothesisIdentifier, ValidationRunIdentifier


@dataclass(frozen=True)
class HypothesisDemoCompletedEvent:
    """hypothesis.demo.completed ドメインイベント型定義。

    M-12: イベント発行（Pub/Sub 送信）は application 層の責務。domain 層は型定義のみを持つ。
    """

    identifier: ValidationRunIdentifier
    hypothesis: HypothesisIdentifier
    promotable: bool
    demo_period_days: int
    occurred_at: datetime.datetime
    trace: str
