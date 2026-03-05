"""ModelRegistryRepository interface."""

import abc

from signal_generator.domain.enums.model_status import ModelStatus
from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot


class ModelRegistryRepository(abc.ABC):
    """model_registry コレクションへの読み取り専用アクセスインターフェース。"""

    @abc.abstractmethod
    def find_by_status(self, status: ModelStatus) -> ModelSnapshot | None:
        """status を指定して ModelSnapshot を単体取得する (approved モデルの解決に使用)。"""

    @abc.abstractmethod
    def find(self, model_version: str) -> ModelSnapshot | None:
        """model_version を指定して ModelSnapshot を単体取得する。"""

    @abc.abstractmethod
    def search(self, criteria: dict[str, object], limit: int = 100) -> list[ModelSnapshot]:
        """検索条件を受け取り条件に合致する ModelSnapshot を取得する。"""
