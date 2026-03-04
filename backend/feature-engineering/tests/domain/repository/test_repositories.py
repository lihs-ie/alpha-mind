"""Tests for repository ABCs - verify interface definitions."""

from abc import ABC
from inspect import signature


class TestFeatureGenerationRepository:
    def test_is_abstract_class(self) -> None:
        from src.domain.repository.feature_generation_repository import FeatureGenerationRepository

        assert issubclass(FeatureGenerationRepository, ABC)

    def test_has_find_method(self) -> None:
        from src.domain.repository.feature_generation_repository import FeatureGenerationRepository

        assert hasattr(FeatureGenerationRepository, "find")
        params = list(signature(FeatureGenerationRepository.find).parameters.keys())
        assert "identifier" in params

    def test_has_find_by_status_method(self) -> None:
        from src.domain.repository.feature_generation_repository import FeatureGenerationRepository

        assert hasattr(FeatureGenerationRepository, "find_by_status")
        params = list(signature(FeatureGenerationRepository.find_by_status).parameters.keys())
        assert "status" in params

    def test_has_search_method(self) -> None:
        from src.domain.repository.feature_generation_repository import FeatureGenerationRepository

        assert hasattr(FeatureGenerationRepository, "search")

    def test_has_persist_method(self) -> None:
        from src.domain.repository.feature_generation_repository import FeatureGenerationRepository

        assert hasattr(FeatureGenerationRepository, "persist")
        params = list(signature(FeatureGenerationRepository.persist).parameters.keys())
        assert "feature_generation" in params

    def test_has_terminate_method(self) -> None:
        from src.domain.repository.feature_generation_repository import FeatureGenerationRepository

        assert hasattr(FeatureGenerationRepository, "terminate")
        params = list(signature(FeatureGenerationRepository.terminate).parameters.keys())
        assert "identifier" in params

    def test_cannot_instantiate_directly(self) -> None:
        import pytest
        from src.domain.repository.feature_generation_repository import FeatureGenerationRepository

        with pytest.raises(TypeError):
            FeatureGenerationRepository()  # type: ignore[abstract]


class TestFeatureDispatchRepository:
    def test_is_abstract_class(self) -> None:
        from src.domain.repository.feature_dispatch_repository import FeatureDispatchRepository

        assert issubclass(FeatureDispatchRepository, ABC)

    def test_has_find_method(self) -> None:
        from src.domain.repository.feature_dispatch_repository import FeatureDispatchRepository

        assert hasattr(FeatureDispatchRepository, "find")

    def test_has_persist_method(self) -> None:
        from src.domain.repository.feature_dispatch_repository import FeatureDispatchRepository

        assert hasattr(FeatureDispatchRepository, "persist")

    def test_has_terminate_method(self) -> None:
        from src.domain.repository.feature_dispatch_repository import FeatureDispatchRepository

        assert hasattr(FeatureDispatchRepository, "terminate")


class TestMarketDataRepository:
    def test_is_abstract_class(self) -> None:
        from src.domain.repository.market_data_repository import MarketDataRepository

        assert issubclass(MarketDataRepository, ABC)

    def test_has_find_method(self) -> None:
        from src.domain.repository.market_data_repository import MarketDataRepository

        assert hasattr(MarketDataRepository, "find")

    def test_has_find_by_target_date_method(self) -> None:
        from src.domain.repository.market_data_repository import MarketDataRepository

        assert hasattr(MarketDataRepository, "find_by_target_date")
        params = list(signature(MarketDataRepository.find_by_target_date).parameters.keys())
        assert "target_date" in params


class TestInsightRecordRepository:
    def test_is_abstract_class(self) -> None:
        from src.domain.repository.insight_record_repository import InsightRecordRepository

        assert issubclass(InsightRecordRepository, ABC)

    def test_has_search_method(self) -> None:
        from src.domain.repository.insight_record_repository import InsightRecordRepository

        assert hasattr(InsightRecordRepository, "search")

    def test_has_find_by_target_date_method(self) -> None:
        from src.domain.repository.insight_record_repository import InsightRecordRepository

        assert hasattr(InsightRecordRepository, "find_by_target_date")


class TestFeatureArtifactRepository:
    def test_is_abstract_class(self) -> None:
        from src.domain.repository.feature_artifact_repository import FeatureArtifactRepository

        assert issubclass(FeatureArtifactRepository, ABC)

    def test_has_persist_method(self) -> None:
        from src.domain.repository.feature_artifact_repository import FeatureArtifactRepository

        assert hasattr(FeatureArtifactRepository, "persist")

    def test_has_find_method(self) -> None:
        from src.domain.repository.feature_artifact_repository import FeatureArtifactRepository

        assert hasattr(FeatureArtifactRepository, "find")

    def test_has_terminate_method(self) -> None:
        from src.domain.repository.feature_artifact_repository import FeatureArtifactRepository

        assert hasattr(FeatureArtifactRepository, "terminate")


class TestIdempotencyKeyRepository:
    def test_is_abstract_class(self) -> None:
        from src.domain.repository.idempotency_key_repository import IdempotencyKeyRepository

        assert issubclass(IdempotencyKeyRepository, ABC)

    def test_has_find_method(self) -> None:
        from src.domain.repository.idempotency_key_repository import IdempotencyKeyRepository

        assert hasattr(IdempotencyKeyRepository, "find")

    def test_has_persist_method(self) -> None:
        from src.domain.repository.idempotency_key_repository import IdempotencyKeyRepository

        assert hasattr(IdempotencyKeyRepository, "persist")

    def test_has_terminate_method(self) -> None:
        from src.domain.repository.idempotency_key_repository import IdempotencyKeyRepository

        assert hasattr(IdempotencyKeyRepository, "terminate")
