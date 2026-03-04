"""MLflow model loader for loading models from MLflow Model Registry."""

from __future__ import annotations

from typing import Any


class ModelLoadError(Exception):
    """MLflow からのモデルロードに失敗した場合の例外。"""


class MLflowModelLoader:
    """MLflow Model Registry から推論用モデルをロードする。"""

    def __init__(self, tracking_uri: str) -> None:
        import mlflow

        mlflow.set_tracking_uri(tracking_uri)

    def load(
        self,
        model_name: str,
        version: str | None = None,
        stage: str | None = None,
    ) -> Any:
        """モデルを MLflow Registry からロードして返す。

        version または stage のいずれかを指定する必要がある。
        """
        import mlflow

        if version is None and stage is None:
            raise ValueError("version または stage のいずれかを指定する必要がある")

        model_identifier = version if version is not None else stage
        model_uri = f"models:/{model_name}/{model_identifier}"

        try:
            return mlflow.pyfunc.load_model(model_uri=model_uri)
        except Exception as error:
            raise ModelLoadError(f"モデル '{model_name}' (uri={model_uri}) のロードに失敗: {error}") from error
