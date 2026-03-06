"""MLflow model loader for loading models from MLflow Model Registry."""

from __future__ import annotations

from typing import Any

from signal_generator.domain.ports.model_loader import ModelLoader


class ModelLoadError(Exception):
    """MLflow からのモデルロードに失敗した場合の例外。"""


class MLflowModelLoader(ModelLoader):
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
        version が指定された場合、MLflow Registry から最新バージョン番号を解決する。
        """
        import mlflow

        if version is None and stage is None:
            raise ValueError("version または stage のいずれかを指定する必要がある")

        try:
            if version is not None:
                model_uri = self._resolve_latest_model_uri(model_name)
            else:
                model_uri = f"models:/{model_name}/{stage}"
            return mlflow.pyfunc.load_model(model_uri=model_uri)
        except Exception as error:
            sanitized_message = str(error)[:200]
            raise ModelLoadError(f"モデル '{model_name}' のロードに失敗: {sanitized_message}") from error

    @staticmethod
    def _resolve_latest_model_uri(model_name: str) -> str:
        """MLflow Registry から最新バージョンの URI を解決する。"""
        import mlflow

        client = mlflow.tracking.MlflowClient()
        versions = client.search_model_versions(f"name='{model_name}'", order_by=["version_number DESC"], max_results=1)
        if not versions:
            raise ModelLoadError(f"モデル '{model_name}' が MLflow Registry に見つからない")
        latest_version = versions[0].version
        return f"models:/{model_name}/{latest_version}"
