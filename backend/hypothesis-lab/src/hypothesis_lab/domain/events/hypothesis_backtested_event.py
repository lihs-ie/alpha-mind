"""HypothesisBacktestedEvent domain event type definition."""

import datetime
from dataclasses import dataclass

from hypothesis_lab.domain.identifiers import HypothesisIdentifier, ValidationRunIdentifier


@dataclass(frozen=True)
class HypothesisBacktestedEvent:
    """hypothesis.backtested ドメインイベント型定義。

    M-12: イベント発行（Pub/Sub 送信）は application 層の責務。domain 層は型定義のみを持つ。
    """

    identifier: ValidationRunIdentifier
    hypothesis: HypothesisIdentifier
    passed: bool
    cost_adjusted_return: float
    dsr: float
    pbo: float
    occurred_at: datetime.datetime
    trace: str
