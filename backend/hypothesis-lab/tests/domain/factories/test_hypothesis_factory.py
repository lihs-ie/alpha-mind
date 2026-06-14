"""Tests for HypothesisFactory."""

import datetime

import pytest

from hypothesis_lab.domain.enums.hypothesis_status import HypothesisStatus
from hypothesis_lab.domain.enums.instrument_type import InstrumentType
from hypothesis_lab.domain.factories.hypothesis_factory import HypothesisFactory


class TestHypothesisFactory:
    def test_valid_input_creates_draft_hypothesis(self) -> None:
        """AC-07 positive path: valid event payload creates a Hypothesis in DRAFT status."""
        hypothesis = HypothesisFactory.from_proposed_event({
            "identifier": "01HXXXXXXXXXXXXXXXXXXX",
            "symbol": "1234",
            "instrumentType": "etf",
            "title": "Valid Hypothesis Title",
            "sourceEvidence": ["insight-001", "insight-002"],
            "skillVersion": "v1.0.0",
            "instructionProfileVersion": "v1.0.0",
            "insiderRisk": None,
            "updatedAt": datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
            "trace": "01HXXXXXXXXXXXXXXXXXXTRACE",
        })
        assert hypothesis.status == HypothesisStatus.DRAFT
        assert hypothesis.identifier == "01HXXXXXXXXXXXXXXXXXXX"
        assert hypothesis.title == "Valid Hypothesis Title"
        assert hypothesis.instrument_type == InstrumentType.ETF

    def test_snake_case_keys_are_supported_as_fallback(self) -> None:
        """snake_case fallback keys work when camelCase keys are absent."""
        hypothesis = HypothesisFactory.from_proposed_event({
            "identifier": "01HXXXXXXXXXXXXXXXXXXX",
            "symbol": "1234",
            "instrument_type": "etf",
            "title": "Valid Hypothesis Title",
            "source_evidence": ["insight-001"],
            "skill_version": "v1.0.0",
            "instruction_profile_version": "v1.0.0",
            "updated_at": datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
        })
        assert hypothesis.status == HypothesisStatus.DRAFT
        assert hypothesis.identifier == "01HXXXXXXXXXXXXXXXXXXX"

    def test_missing_title_raises_value_error(self) -> None:
        """AC-07: missing title -> ValueError."""
        with pytest.raises(ValueError):
            HypothesisFactory.from_proposed_event({
                "identifier": "01HXXXXXXXXXXXXXXXXXXX",
                "symbol": "1234",
                "instrumentType": "etf",
                "title": "",  # Empty title is invalid
                "sourceEvidence": ["insight-001"],
                "skillVersion": "v1.0.0",
                "instructionProfileVersion": "v1.0.0",
                "updatedAt": datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
                "trace": "01HXXXXXXXXXXXXXXXXXXTRACE",
            })

    def test_empty_source_evidence_raises_value_error(self) -> None:
        """AC-07: missing source_evidence -> ValueError."""
        with pytest.raises(ValueError):
            HypothesisFactory.from_proposed_event({
                "identifier": "01HXXXXXXXXXXXXXXXXXXX",
                "symbol": "1234",
                "instrumentType": "etf",
                "title": "Valid Title",
                "sourceEvidence": [],  # Empty list is invalid
                "skillVersion": "v1.0.0",
                "instructionProfileVersion": "v1.0.0",
                "updatedAt": datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
                "trace": "01HXXXXXXXXXXXXXXXXXXTRACE",
            })

    def test_missing_skill_version_raises_value_error(self) -> None:
        """AC-07: missing skill_version -> ValueError."""
        with pytest.raises(ValueError):
            HypothesisFactory.from_proposed_event({
                "identifier": "01HXXXXXXXXXXXXXXXXXXX",
                "symbol": "1234",
                "instrumentType": "etf",
                "title": "Valid Title",
                "sourceEvidence": ["insight-001"],
                "skillVersion": "",  # Empty is invalid
                "instructionProfileVersion": "v1.0.0",
                "updatedAt": datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
                "trace": "01HXXXXXXXXXXXXXXXXXXTRACE",
            })

    def test_missing_instruction_profile_version_raises_value_error(self) -> None:
        """AC-07: missing instruction_profile_version -> ValueError."""
        with pytest.raises(ValueError):
            HypothesisFactory.from_proposed_event({
                "identifier": "01HXXXXXXXXXXXXXXXXXXX",
                "symbol": "1234",
                "instrumentType": "etf",
                "title": "Valid Title",
                "sourceEvidence": ["insight-001"],
                "skillVersion": "v1.0.0",
                "instructionProfileVersion": "",  # Empty is invalid
                "updatedAt": datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc),
                "trace": "01HXXXXXXXXXXXXXXXXXXTRACE",
            })

    def test_initial_status_is_draft(self) -> None:
        """Factory always creates Hypothesis with DRAFT status."""
        hypothesis = HypothesisFactory.from_proposed_event({
            "identifier": "01HXXXXXXXXXXXXXXXXXXX",
            "symbol": "5678",
            "instrumentType": "stock",
            "title": "Stock Hypothesis",
            "sourceEvidence": ["insight-001"],
            "skillVersion": "v2.0.0",
            "instructionProfileVersion": "v2.0.0",
            "updatedAt": datetime.datetime(2026, 6, 1, tzinfo=datetime.timezone.utc),
            "trace": "01HXXXXXXXXXXXXXXXXXXTRACE",
        })
        assert hypothesis.status == HypothesisStatus.DRAFT
