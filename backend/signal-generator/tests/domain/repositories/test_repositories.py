"""Tests for repository interfaces (ABC)."""

import datetime

import pytest

from signal_generator.domain.aggregates.signal_generation import SignalGeneration
from signal_generator.domain.enums.generation_status import GenerationStatus
from signal_generator.domain.enums.model_status import ModelStatus
from signal_generator.domain.repositories.idempotency_key_repository import IdempotencyKeyRepository
from signal_generator.domain.repositories.model_registry_repository import ModelRegistryRepository
from signal_generator.domain.repositories.signal_dispatch_repository import SignalDispatchRepository
from signal_generator.domain.repositories.signal_generation_repository import SignalGenerationRepository
from signal_generator.domain.value_objects.feature_snapshot import FeatureSnapshot
from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot


def _make_feature_snapshot() -> FeatureSnapshot:
    return FeatureSnapshot(
        target_date=datetime.date(2026, 1, 1),
        feature_version="v1.0.0",
        storage_path="gs://feature_store/2026-01-01/features.parquet",
    )


class TestSignalGenerationRepositoryIsAbstract:
    def test_cannot_instantiate_directly(self) -> None:
        with pytest.raises(TypeError):
            SignalGenerationRepository()  # type: ignore[abstract]

    def test_has_find_method(self) -> None:
        assert hasattr(SignalGenerationRepository, "find")

    def test_has_find_by_status_method(self) -> None:
        assert hasattr(SignalGenerationRepository, "find_by_status")

    def test_has_search_method(self) -> None:
        assert hasattr(SignalGenerationRepository, "search")

    def test_has_persist_method(self) -> None:
        assert hasattr(SignalGenerationRepository, "persist")

    def test_has_terminate_method(self) -> None:
        assert hasattr(SignalGenerationRepository, "terminate")

    def test_concrete_implementation_must_implement_all_methods(self) -> None:
        """抽象メソッドを実装せずにインスタンス化しようとするとエラーになる。"""

        class IncompleteRepository(SignalGenerationRepository):
            pass

        with pytest.raises(TypeError):
            IncompleteRepository()  # type: ignore[abstract]

    def test_concrete_implementation_can_be_instantiated(self) -> None:
        class ConcreteRepository(SignalGenerationRepository):
            def find(self, identifier: str) -> SignalGeneration | None:
                return None

            def find_by_status(self, status: GenerationStatus) -> list[SignalGeneration]:
                return []

            def search(self, criteria: dict) -> list[SignalGeneration]:  # type: ignore[type-arg]
                return []

            def persist(self, signal_generation: SignalGeneration) -> None:
                pass

            def terminate(self, identifier: str) -> None:
                pass

        repo = ConcreteRepository()
        assert repo is not None


class TestSignalDispatchRepositoryIsAbstract:
    def test_cannot_instantiate_directly(self) -> None:
        with pytest.raises(TypeError):
            SignalDispatchRepository()  # type: ignore[abstract]

    def test_has_find_method(self) -> None:
        assert hasattr(SignalDispatchRepository, "find")

    def test_has_persist_method(self) -> None:
        assert hasattr(SignalDispatchRepository, "persist")

    def test_has_terminate_method(self) -> None:
        assert hasattr(SignalDispatchRepository, "terminate")


class TestModelRegistryRepositoryIsAbstract:
    def test_cannot_instantiate_directly(self) -> None:
        with pytest.raises(TypeError):
            ModelRegistryRepository()  # type: ignore[abstract]

    def test_has_find_by_status_method(self) -> None:
        assert hasattr(ModelRegistryRepository, "find_by_status")

    def test_has_find_method(self) -> None:
        assert hasattr(ModelRegistryRepository, "find")

    def test_has_search_method(self) -> None:
        assert hasattr(ModelRegistryRepository, "search")

    def test_concrete_implementation_returns_model_snapshot(self) -> None:
        class ConcreteModelRegistry(ModelRegistryRepository):
            def find_by_status(self, status: ModelStatus) -> ModelSnapshot | None:
                if status == ModelStatus.APPROVED:
                    return ModelSnapshot(
                        model_version="model-v1.0.0",
                        status=ModelStatus.APPROVED,
                        approved_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
                    )
                return None

            def find(self, model_version: str) -> ModelSnapshot | None:
                return None

            def search(self, criteria: dict) -> list[ModelSnapshot]:  # type: ignore[type-arg]
                return []

        repo = ConcreteModelRegistry()
        result = repo.find_by_status(ModelStatus.APPROVED)
        assert result is not None
        assert result.status == ModelStatus.APPROVED


class TestIdempotencyKeyRepositoryIsAbstract:
    def test_cannot_instantiate_directly(self) -> None:
        with pytest.raises(TypeError):
            IdempotencyKeyRepository()  # type: ignore[abstract]

    def test_has_find_method(self) -> None:
        assert hasattr(IdempotencyKeyRepository, "find")

    def test_has_persist_method(self) -> None:
        assert hasattr(IdempotencyKeyRepository, "persist")

    def test_has_terminate_method(self) -> None:
        assert hasattr(IdempotencyKeyRepository, "terminate")

    def test_concrete_implementation_checks_existence(self) -> None:
        class ConcreteIdempotencyKeyRepository(IdempotencyKeyRepository):
            def __init__(self) -> None:
                self._stored: set[str] = set()

            def find(self, identifier: str) -> bool:
                return identifier in self._stored

            def persist(self, identifier: str, processed_at: datetime.datetime) -> None:
                self._stored.add(identifier)

            def terminate(self, identifier: str) -> None:
                self._stored.discard(identifier)

        repo = ConcreteIdempotencyKeyRepository()
        assert repo.find("01JNABCDEF1234567890123456") is False
        repo.persist("01JNABCDEF1234567890123456", datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC))
        assert repo.find("01JNABCDEF1234567890123456") is True
