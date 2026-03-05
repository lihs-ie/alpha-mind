"""IdempotencyKeyRepository interface."""

import abc
import datetime


class IdempotencyKeyRepository(abc.ABC):
    """冪等性キー (処理済みイベント管理) のリポジトリインターフェース。

    RULE-SG-003: 同一イベント identifier は1回のみ処理する。
    """

    @abc.abstractmethod
    def find(self, identifier: str) -> bool:
        """identifier が処理済みかどうかを返す。処理済みなら True。"""

    @abc.abstractmethod
    def persist(self, identifier: str, processed_at: datetime.datetime, trace: str) -> bool:
        """identifier を処理済みとして登録する。

        Returns:
            True: 新規登録成功。
            False: 既に処理済み(重複イベント)。副作用なく成功扱い。
        """

    @abc.abstractmethod
    def terminate(self, identifier: str) -> None:
        """identifier の処理済み記録を削除する。"""
