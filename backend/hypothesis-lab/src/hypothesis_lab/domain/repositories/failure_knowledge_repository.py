"""FailureKnowledgeRepository interface."""

import abc

from hypothesis_lab.domain.aggregates.failure_knowledge import FailureKnowledge
from hypothesis_lab.domain.enums.reason_code import ReasonCode
from hypothesis_lab.domain.identifiers import FailureKnowledgeIdentifier
from hypothesis_lab.domain.repositories.criteria import FailureKnowledgeSearchCriteria


class FailureKnowledgeRepository(abc.ABC):
    """FailureKnowledge エンティティの永続化インターフェース。IO 実装は含めない。"""

    @abc.abstractmethod
    def find(self, identifier: FailureKnowledgeIdentifier) -> FailureKnowledge | None:
        """identifier を指定して FailureKnowledge を単体取得する。"""

    @abc.abstractmethod
    def find_by_reason_code(self, reason_code: ReasonCode) -> list[FailureKnowledge]:
        """reason_code を指定して FailureKnowledge を取得する。"""

    @abc.abstractmethod
    def search(self, criteria: FailureKnowledgeSearchCriteria) -> list[FailureKnowledge]:
        """検索条件を受け取り条件に合致する FailureKnowledge を全て取得する。"""

    @abc.abstractmethod
    def persist(self, failure_knowledge: FailureKnowledge) -> None:
        """FailureKnowledge を永続化する。"""

    @abc.abstractmethod
    def terminate(self, identifier: FailureKnowledgeIdentifier) -> None:
        """identifier を指定して FailureKnowledge を削除する。"""
