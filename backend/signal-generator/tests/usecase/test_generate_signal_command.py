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
        command_fields = {
            "identifier": "01JNABCDEF1234567890123456",
            "target_date": datetime.date(2026, 3, 5),
            "feature_version": "v1.0.0",
            "storage_path": "gs://feature_store/2026-03-05/features.parquet",
            "universe_count": 100,
            "trace": "trace-001",
        }
        command_a = GenerateSignalCommand(**command_fields)
        command_b = GenerateSignalCommand(**command_fields)

        assert command_a == command_b


class TestGenerateSignalCommandValidation:
    """GenerateSignalCommand のバリデーションテスト。"""

    def test_empty_identifier_raises_error(self) -> None:
        with pytest.raises(ValueError, match="identifier is required"):
            GenerateSignalCommand(
                identifier="",
                target_date=datetime.date(2026, 3, 5),
                feature_version="v1.0.0",
                storage_path="gs://feature_store/2026-03-05/features.parquet",
                universe_count=100,
                trace="trace-001",
            )

    def test_empty_trace_raises_error(self) -> None:
        with pytest.raises(ValueError, match="trace is required"):
            GenerateSignalCommand(
                identifier="01JNABCDEF1234567890123456",
                target_date=datetime.date(2026, 3, 5),
                feature_version="v1.0.0",
                storage_path="gs://feature_store/2026-03-05/features.parquet",
                universe_count=100,
                trace="",
            )

    def test_zero_universe_count_raises_error(self) -> None:
        with pytest.raises(ValueError, match="universe_count must be positive"):
            GenerateSignalCommand(
                identifier="01JNABCDEF1234567890123456",
                target_date=datetime.date(2026, 3, 5),
                feature_version="v1.0.0",
                storage_path="gs://feature_store/2026-03-05/features.parquet",
                universe_count=0,
                trace="trace-001",
            )

    def test_negative_universe_count_raises_error(self) -> None:
        with pytest.raises(ValueError, match="universe_count must be positive"):
            GenerateSignalCommand(
                identifier="01JNABCDEF1234567890123456",
                target_date=datetime.date(2026, 3, 5),
                feature_version="v1.0.0",
                storage_path="gs://feature_store/2026-03-05/features.parquet",
                universe_count=-1,
                trace="trace-001",
            )
