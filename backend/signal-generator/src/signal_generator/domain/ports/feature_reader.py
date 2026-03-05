"""FeatureReader port."""

import abc

import pandas


class FeatureReader(abc.ABC):
    """特徴量ストアから Parquet ファイルを読み込むポート。"""

    @abc.abstractmethod
    def read(self, storage_path: str) -> pandas.DataFrame:
        """storage_path から特徴量 DataFrame を読み込む。"""
