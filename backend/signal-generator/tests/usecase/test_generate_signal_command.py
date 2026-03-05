"""Tests for GenerateSignalCommand DTO."""

import datetime

import pytest

from signal_generator.usecase.generate_signal_command import GenerateSignalCommand


class TestGenerateSignalCommandCreation:
    """GenerateSignalCommand の作成テスト。"""

    def test_create_with_required_fields(self) -> None:
        command = GenerateSignalCommand(
            identifier="01JNABCDEF1234567890123456",
            target_date=datetime.date(2026, 3, 5),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-03-05/features.parquet",
            universe_count=100,
            trace="trace-001",
        )

        assert command.identifier == "01JNABCDEF1234567890123456"
        assert command.target_date == datetime.date(2026, 3, 5)
        assert command.feature_version == "v1.0.0"
        assert command.storage_path == "gs://feature_store/2026-03-05/features.parquet"
        assert command.universe_count == 100
        assert command.trace == "trace-001"

    def test_immutability(self) -> None:
        command = GenerateSignalCommand(
            identifier="01JNABCDEF1234567890123456",
            target_date=datetime.date(2026, 3, 5),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-03-05/features.parquet",
            universe_count=100,
            trace="trace-001",
        )

        with pytest.raises(AttributeError):
            command.identifier = "changed"  # type: ignore[misc]

    def test_equality_by_value(self) -> None:
        args = {
            "identifier": "01JNABCDEF1234567890123456",
            "target_date": datetime.date(2026, 3, 5),
            "feature_version": "v1.0.0",
            "storage_path": "gs://feature_store/2026-03-05/features.parquet",
            "universe_count": 100,
            "trace": "trace-001",
        }
        command_a = GenerateSignalCommand(**args)
        command_b = GenerateSignalCommand(**args)

        assert command_a == command_b
