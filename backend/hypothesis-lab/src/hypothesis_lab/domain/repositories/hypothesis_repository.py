"""HypothesisRepository interface."""

import abc

from hypothesis_lab.domain.aggregates.hypothesis import Hypothesis
from hypothesis_lab.domain.enums.hypothesis_status import HypothesisStatus
from hypothesis_lab.domain.identifiers import HypothesisIdentifier
from hypothesis_lab.domain.repositories.criteria import HypothesisSearchCriteria


class HypothesisRepository(abc.ABC):
    """Hypothesis 集約の永続化インターフェース。IO 実装は含めない。"""

    @abc.abstractmethod
    def find(self, identifier: HypothesisIdentifier) -> Hypothesis | None:
        """identifier を指定して Hypothesis を単体取得する。"""

    @abc.abstractmethod
    def find_by_status(self, status: HypothesisStatus) -> list[Hypothesis]:
        """status を指定して Hypothesis を取得する。"""

    @abc.abstractmethod
    def search(self, criteria: HypothesisSearchCriteria) -> list[Hypothesis]:
        """検索条件を受け取り条件に合致する Hypothesis を全て取得する。"""

    @abc.abstractmethod
    def persist(self, hypothesis: Hypothesis) -> None:
        """Hypothesis を永続化する。"""

    @abc.abstractmethod
    def terminate(self, identifier: HypothesisIdentifier) -> None:
        """identifier を指定して Hypothesis を削除する。"""
