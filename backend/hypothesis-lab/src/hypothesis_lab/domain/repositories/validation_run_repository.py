"""ValidationRunRepository interface."""

import abc

from hypothesis_lab.domain.aggregates.validation_run import ValidationRun
from hypothesis_lab.domain.enums.run_type import RunType
from hypothesis_lab.domain.identifiers import HypothesisIdentifier, ValidationRunIdentifier
from hypothesis_lab.domain.repositories.criteria import ValidationRunSearchCriteria


class ValidationRunRepository(abc.ABC):
    """ValidationRun 集約の永続化インターフェース。IO 実装は含めない。"""

    @abc.abstractmethod
    def find(self, identifier: ValidationRunIdentifier) -> ValidationRun | None:
        """identifier を指定して ValidationRun を単体取得する。"""

    @abc.abstractmethod
    def find_by_run_type(self, hypothesis: HypothesisIdentifier, run_type: RunType) -> list[ValidationRun]:
        """hypothesis 識別子と run_type を指定して ValidationRun を取得する。"""

    @abc.abstractmethod
    def search(self, criteria: ValidationRunSearchCriteria) -> list[ValidationRun]:
        """検索条件を受け取り条件に合致する ValidationRun を全て取得する。"""

    @abc.abstractmethod
    def persist(self, validation_run: ValidationRun) -> None:
        """ValidationRun を永続化する。"""

    @abc.abstractmethod
    def terminate(self, identifier: ValidationRunIdentifier) -> None:
        """identifier を指定して ValidationRun を削除する。"""
