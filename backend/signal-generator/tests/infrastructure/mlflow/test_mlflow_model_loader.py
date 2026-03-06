"""Tests for MLflowModelLoader."""

import sys
from unittest.mock import MagicMock, patch

import pytest


def _create_mock_mlflow() -> MagicMock:
    """テスト用の mlflow モックモジュールを作成する。"""
    mock_mlflow = MagicMock()
    return mock_mlflow


class TestMLflowModelLoader:
    """MLflowModelLoader のテスト。"""

    def test_load_returns_model_from_registry(self) -> None:
        mock_mlflow = _create_mock_mlflow()
        mock_model = MagicMock()
        mock_mlflow.pyfunc.load_model.return_value = mock_model
        mock_version = MagicMock()
        mock_version.version = "3"
        mock_mlflow.tracking.MlflowClient.return_value.search_model_versions.return_value = [mock_version]

        with patch.dict(sys.modules, {"mlflow": mock_mlflow}):
            from signal_generator.infrastructure.mlflow.mlflow_model_loader import (
                MLflowModelLoader,
            )

            loader = MLflowModelLoader(tracking_uri="http://localhost:5000")
            mock_mlflow.set_tracking_uri.assert_called_once_with("http://localhost:5000")

            result = loader.load("my-model", "v1.0.0")

            mock_mlflow.pyfunc.load_model.assert_called_once_with(model_uri="models:/my-model/3")
            assert result is mock_model

    def test_load_raises_model_load_error_on_exception(self) -> None:
        mock_mlflow = _create_mock_mlflow()
        mock_version = MagicMock()
        mock_version.version = "1"
        mock_mlflow.tracking.MlflowClient.return_value.search_model_versions.return_value = [mock_version]
        mock_mlflow.pyfunc.load_model.side_effect = Exception("Model not found")

        with patch.dict(sys.modules, {"mlflow": mock_mlflow}):
            from signal_generator.infrastructure.mlflow.mlflow_model_loader import (
                MLflowModelLoader,
                ModelLoadError,
            )

            loader = MLflowModelLoader(tracking_uri="http://localhost:5000")

            with pytest.raises(ModelLoadError, match="my-model"):
                loader.load("my-model", "v1.0.0")

    def test_load_with_stage_instead_of_version(self) -> None:
        mock_mlflow = _create_mock_mlflow()
        mock_model = MagicMock()
        mock_mlflow.pyfunc.load_model.return_value = mock_model

        with patch.dict(sys.modules, {"mlflow": mock_mlflow}):
            from signal_generator.infrastructure.mlflow.mlflow_model_loader import (
                MLflowModelLoader,
            )

            loader = MLflowModelLoader(tracking_uri="http://localhost:5000")
            result = loader.load("my-model", stage="Production")

            mock_mlflow.pyfunc.load_model.assert_called_once_with(model_uri="models:/my-model/Production")
            assert result is mock_model

    def test_load_raises_value_error_when_no_version_or_stage(self) -> None:
        mock_mlflow = _create_mock_mlflow()

        with patch.dict(sys.modules, {"mlflow": mock_mlflow}):
            from signal_generator.infrastructure.mlflow.mlflow_model_loader import (
                MLflowModelLoader,
            )

            loader = MLflowModelLoader(tracking_uri="http://localhost:5000")

            with pytest.raises(ValueError, match=r"version.*stage"):
                loader.load("my-model")

    def test_predict_delegates_to_loaded_model(self) -> None:
        """MLflow pyfunc モデルの predict メソッドが DataFrame を受け取ることを確認する。"""
        mock_mlflow = _create_mock_mlflow()
        mock_model = MagicMock()
        mock_predictions = MagicMock()
        mock_model.predict.return_value = mock_predictions
        mock_mlflow.pyfunc.load_model.return_value = mock_model
        mock_version = MagicMock()
        mock_version.version = "1"
        mock_mlflow.tracking.MlflowClient.return_value.search_model_versions.return_value = [mock_version]
        mock_dataframe = MagicMock()

        with patch.dict(sys.modules, {"mlflow": mock_mlflow}):
            from signal_generator.infrastructure.mlflow.mlflow_model_loader import (
                MLflowModelLoader,
            )

            loader = MLflowModelLoader(tracking_uri="http://localhost:5000")
            model = loader.load("my-model", "v1.0.0")
            result = model.predict(mock_dataframe)

            mock_model.predict.assert_called_once_with(mock_dataframe)
            assert result is mock_predictions
