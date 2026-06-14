"""Tests for DependencyContainer for hypothesis-lab service."""

from __future__ import annotations

import os
from unittest.mock import patch

import pytest

from application.hypothesis_workflow_service import HypothesisWorkflowService
from presentation.dependency_container import DependencyContainer


class TestDependencyContainer:
    """Tests for DependencyContainer DI wiring."""

    @staticmethod
    def _make_env_vars() -> dict[str, str]:
        return {
            "GCP_PROJECT_ID": "test-project",
            "HYPOTHESIS_BACKTESTED_TOPIC": "event-hypothesis-backtested-v1",
            "HYPOTHESIS_PROMOTED_TOPIC": "event-hypothesis-promoted-v1",
            "HYPOTHESIS_REJECTED_TOPIC": "event-hypothesis-rejected-v1",
        }

    def test_hypothesis_workflow_service_is_created(self) -> None:
        env = self._make_env_vars()
        with patch.dict(os.environ, env, clear=False):
            container = DependencyContainer()
            service = container.hypothesis_workflow_service()

        assert isinstance(service, HypothesisWorkflowService)

    def test_hypothesis_workflow_service_returns_same_instance(self) -> None:
        env = self._make_env_vars()
        with patch.dict(os.environ, env, clear=False):
            container = DependencyContainer()
            service_first = container.hypothesis_workflow_service()
            service_second = container.hypothesis_workflow_service()

        assert service_first is service_second

    def test_missing_gcp_project_id_raises_error(self) -> None:
        env = self._make_env_vars()
        del env["GCP_PROJECT_ID"]
        with patch.dict(os.environ, env, clear=True), pytest.raises(OSError, match="GCP_PROJECT_ID"):
            DependencyContainer()

    def test_missing_backtested_topic_uses_default(self) -> None:
        env = self._make_env_vars()
        del env["HYPOTHESIS_BACKTESTED_TOPIC"]
        with patch.dict(os.environ, env, clear=True):
            container = DependencyContainer()
        assert container._hypothesis_backtested_topic == "event-hypothesis-backtested-v1"

    def test_missing_promoted_topic_uses_default(self) -> None:
        env = self._make_env_vars()
        del env["HYPOTHESIS_PROMOTED_TOPIC"]
        with patch.dict(os.environ, env, clear=True):
            container = DependencyContainer()
        assert container._hypothesis_promoted_topic == "event-hypothesis-promoted-v1"

    def test_missing_rejected_topic_uses_default(self) -> None:
        env = self._make_env_vars()
        del env["HYPOTHESIS_REJECTED_TOPIC"]
        with patch.dict(os.environ, env, clear=True):
            container = DependencyContainer()
        assert container._hypothesis_rejected_topic == "event-hypothesis-rejected-v1"

    def test_partner_restricted_symbols_defaults_to_empty(self) -> None:
        env = self._make_env_vars()
        with patch.dict(os.environ, env, clear=False):
            if "PARTNER_RESTRICTED_SYMBOLS" in os.environ:
                del os.environ["PARTNER_RESTRICTED_SYMBOLS"]
            container = DependencyContainer()

        # Access via the private attribute to confirm default behavior
        assert container._partner_restricted_symbols == []

    def test_partner_restricted_symbols_parsed_from_env(self) -> None:
        env = {**self._make_env_vars(), "PARTNER_RESTRICTED_SYMBOLS": "7203, 6758 , 9984"}
        with patch.dict(os.environ, env, clear=False):
            container = DependencyContainer()

        assert container._partner_restricted_symbols == ["7203", "6758", "9984"]
