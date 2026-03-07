"""ModelLoader port."""

from __future__ import annotations

import abc
from typing import Any


class ModelLoader(abc.ABC):
    """推論用モデルをロードするポート。"""

    @abc.abstractmethod
    def load(
        self,
        model_name: str,
        version: str | None = None,
        stage: str | None = None,
    ) -> Any:
        """モデルをロードして返す。

        version または stage が省略された場合は、model_name に紐づく最新登録版を解決する。
        """
