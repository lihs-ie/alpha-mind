"""SignalWriter port."""

import abc

import pandas


class SignalWriter(abc.ABC):
    """推論結果を Parquet 形式で書き出すポート。"""

    @abc.abstractmethod
    def write(self, dataframe: pandas.DataFrame, storage_path: str) -> None:
        """DataFrame を storage_path に書き出す。"""
