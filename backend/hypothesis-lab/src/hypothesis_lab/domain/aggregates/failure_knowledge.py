"""FailureKnowledge entity."""

import datetime

from hypothesis_lab.domain.identifiers import FailureKnowledgeIdentifier, HypothesisIdentifier
from hypothesis_lab.domain.value_objects.failure_summary import FailureSummary


class FailureKnowledge:
    """失敗知見を記録するエンティティ。

    AC-10: failure_summary.markdown_summary が非空文字列でなければならない。
    """

    def __init__(
        self,
        identifier: FailureKnowledgeIdentifier,
        hypothesis: HypothesisIdentifier,
        failure_summary: FailureSummary,
        occurred_at: datetime.datetime,
        trace: str,
    ) -> None:
        self._identifier = identifier
        self._hypothesis = hypothesis
        self._failure_summary = failure_summary
        self._occurred_at = occurred_at
        self._trace = trace

    @property
    def identifier(self) -> FailureKnowledgeIdentifier:
        return self._identifier

    @property
    def hypothesis(self) -> HypothesisIdentifier:
        return self._hypothesis

    @property
    def failure_summary(self) -> FailureSummary:
        return self._failure_summary

    @property
    def occurred_at(self) -> datetime.datetime:
        return self._occurred_at

    @property
    def trace(self) -> str:
        return self._trace
