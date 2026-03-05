"""Tests for DependencyContainer."""

from __future__ import annotations

import datetime
import os
from unittest.mock import patch

import pytest

from presentation.dependency_container import DependencyContainer, _UlidFeatureVersionGenerator
from usecase.feature_generation_service import FeatureGenerationService


class TestDependencyContainer:
    """Tests for DependencyContainer DI wiring."""

    @staticmethod
    def _make_env_vars() -> dict[str, str]:
        return {
            "GCP_PROJECT_ID": "test-project",
            "FEATURES_GENERATED_TOPIC": "features-generated",
            "FEATURES_GENERATION_FAILED_TOPIC": "features-generation-failed",
            "FEATURE_STORE_BUCKET": "feature-store-bucket",
        }

    def test_feature_generation_service_is_created(self) -> None:
        env = self._make_env_vars()
        with patch.dict(os.environ, env, clear=False):
            container = DependencyContainer()
            service = container.feature_generation_service()

        assert isinstance(service, FeatureGenerationService)

    def test_feature_generation_service_returns_same_instance(self) -> None:
        env = self._make_env_vars()
        with patch.dict(os.environ, env, clear=False):
            container = DependencyContainer()
            service_first = container.feature_generation_service()
            service_second = container.feature_generation_service()

        assert service_first is service_second

    def test_missing_gcp_project_id_raises_error(self) -> None:
        env = self._make_env_vars()
        del env["GCP_PROJECT_ID"]
        with patch.dict(os.environ, env, clear=True), pytest.raises(EnvironmentError, match="GCP_PROJECT_ID"):
            DependencyContainer()

    def test_missing_features_generated_topic_raises_error(self) -> None:
        env = self._make_env_vars()
        del env["FEATURES_GENERATED_TOPIC"]
        with patch.dict(os.environ, env, clear=True), pytest.raises(EnvironmentError, match="FEATURES_GENERATED_TOPIC"):
            DependencyContainer()

    def test_missing_features_generation_failed_topic_raises_error(self) -> None:
        env = self._make_env_vars()
        del env["FEATURES_GENERATION_FAILED_TOPIC"]
        with patch.dict(os.environ, env, clear=True), pytest.raises(EnvironmentError, match="FEATURES_GENERATION_FAILED_TOPIC"):
            DependencyContainer()

    def test_missing_feature_store_bucket_raises_error(self) -> None:
        env = self._make_env_vars()
        del env["FEATURE_STORE_BUCKET"]
        with patch.dict(os.environ, env, clear=True), pytest.raises(EnvironmentError, match="FEATURE_STORE_BUCKET"):
            DependencyContainer()

class TestUlidFeatureVersionGenerator:
    """Tests for _UlidFeatureVersionGenerator."""

    def test_generate_returns_version_with_date_prefix(self) -> None:
        generator = _UlidFeatureVersionGenerator()
        target_date = datetime.date(2026, 3, 5)
        version = generator.generate(target_date)

        assert version.startswith("v-2026-03-05-")
        # 8 hex characters suffix
        suffix = version.split("-", 4)[-1]
        assert len(suffix) == 8

    def test_generate_produces_unique_versions(self) -> None:
        generator = _UlidFeatureVersionGenerator()
        target_date = datetime.date(2026, 3, 5)
        version_first = generator.generate(target_date)
        version_second = generator.generate(target_date)

        assert version_first != version_second
