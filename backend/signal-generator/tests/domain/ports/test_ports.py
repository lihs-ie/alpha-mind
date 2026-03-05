"""Tests for domain ports (ABC interfaces)."""

import pytest

from signal_generator.domain.ports.event_publisher import SignalEventPublisher
from signal_generator.domain.ports.feature_reader import FeatureReader
from signal_generator.domain.ports.model_loader import ModelLoader
from signal_generator.domain.ports.signal_writer import SignalWriter
from signal_generator.infrastructure.messaging.pubsub_signal_event_publisher import (
    PubSubSignalEventPublisher,
)
from signal_generator.infrastructure.mlflow.mlflow_model_loader import MLflowModelLoader
from signal_generator.infrastructure.storage.cloud_storage_feature_reader import (
    CloudStorageFeatureReader,
)
from signal_generator.infrastructure.storage.cloud_storage_signal_writer import (
    CloudStorageSignalWriter,
)


class TestPortsAreAbstract:
    """ドメインポートが抽象クラスであることを検証する。"""

    def test_signal_event_publisher_cannot_be_instantiated(self) -> None:
        with pytest.raises(TypeError):
            SignalEventPublisher()  # type: ignore[abstract]

    def test_feature_reader_cannot_be_instantiated(self) -> None:
        with pytest.raises(TypeError):
            FeatureReader()  # type: ignore[abstract]

    def test_signal_writer_cannot_be_instantiated(self) -> None:
        with pytest.raises(TypeError):
            SignalWriter()  # type: ignore[abstract]

    def test_model_loader_cannot_be_instantiated(self) -> None:
        with pytest.raises(TypeError):
            ModelLoader()  # type: ignore[abstract]


class TestInfraImplementsPorts:
    """インフラ実装がドメインポートを実装していることを検証する。"""

    def test_pubsub_publisher_implements_signal_event_publisher(self) -> None:
        assert issubclass(PubSubSignalEventPublisher, SignalEventPublisher)

    def test_cloud_storage_feature_reader_implements_feature_reader(self) -> None:
        assert issubclass(CloudStorageFeatureReader, FeatureReader)

    def test_cloud_storage_signal_writer_implements_signal_writer(self) -> None:
        assert issubclass(CloudStorageSignalWriter, SignalWriter)

    def test_mlflow_model_loader_implements_model_loader(self) -> None:
        assert issubclass(MLflowModelLoader, ModelLoader)
