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
        """モデルをロードして返す。version または stage のいずれかを指定する。"""
