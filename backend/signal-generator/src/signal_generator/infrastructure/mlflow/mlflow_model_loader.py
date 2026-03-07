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

        version または stage が未指定の場合は、登録済みの最新 version を解決して使用する。
        """
        import mlflow

        try:
            model_uri = self._build_model_uri(
                mlflow=mlflow,
                model_name=model_name,
                version=version,
                stage=stage,
            )
            return mlflow.pyfunc.load_model(model_uri=model_uri)
        except Exception as error:
            sanitized_message = str(error)[:200]
            raise ModelLoadError(f"モデル '{model_name}' のロードに失敗: {sanitized_message}") from error

    def _build_model_uri(
        self,
        mlflow: Any,
        model_name: str,
        version: str | None,
        stage: str | None,
    ) -> str:
        """MLflow model URI を組み立てる。"""
        if version is not None:
            return f"models:/{model_name}/{version}"

        if stage is not None:
            return f"models:/{model_name}/{stage}"

        latest_version = self._resolve_latest_version(mlflow=mlflow, model_name=model_name)
        return f"models:/{model_name}/{latest_version}"

    def _resolve_latest_version(self, mlflow: Any, model_name: str) -> str:
        """登録モデル名に紐づく最新 version を解決する。"""
        client = mlflow.MlflowClient()
        model_versions = list(client.search_model_versions(filter_string=f"name = '{model_name}'"))
        if not model_versions:
            raise ValueError(f"登録モデル '{model_name}' が見つかりません")

        latest_model_version = max(
            model_versions,
            key=lambda model_version: int(str(model_version.version)),
        )
        return str(latest_model_version.version)
