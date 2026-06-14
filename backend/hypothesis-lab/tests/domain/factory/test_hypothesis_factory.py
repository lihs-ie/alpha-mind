"""Tests for HypothesisFactory (Must-F-01)."""

from __future__ import annotations

import datetime

import pytest

from domain.factory.hypothesis_factory import HypothesisFactory
from domain.value_object.enums import HypothesisStatus, InstrumentType, ReasonCode

_NOW = datetime.datetime(2026, 3, 1, tzinfo=datetime.UTC)
_TRACE = "01JNPQRS000000000000000001"
_IDENTIFIER = "01JNPQRS000000000000000010"


def _make_valid_payload() -> dict[str, object]:
    return {
        "title": "Test ETF hypothesis",
        "sourceEvidence": ["insight-001", "insight-002"],
        "skillVersion": "v1.0.0",
        "instructionProfileVersion": "v1.0.0",
        "symbol": "1234",
        "instrumentType": "ETF",
    }


class TestHypothesisFactoryFromProposedEvent:
    """Must-F-01: fromProposedEvent creates Hypothesis with status=draft."""

    def test_creates_hypothesis_with_status_draft(self) -> None:
        factory = HypothesisFactory()
        payload = _make_valid_payload()
        hypothesis = factory.from_proposed_event(
            event_payload=payload,
            identifier=_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert hypothesis.status == HypothesisStatus.DRAFT

    def test_creates_hypothesis_with_correct_fields(self) -> None:
        factory = HypothesisFactory()
        payload = _make_valid_payload()
        hypothesis = factory.from_proposed_event(
            event_payload=payload,
            identifier=_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert hypothesis.identifier == _IDENTIFIER
        assert hypothesis.title == "Test ETF hypothesis"
        assert hypothesis.source_evidence == ["insight-001", "insight-002"]
        assert hypothesis.skill_version == "v1.0.0"
        assert hypothesis.instruction_profile_version == "v1.0.0"
        assert hypothesis.symbol == "1234"
        assert hypothesis.instrument_type == InstrumentType.ETF

    def test_rejects_missing_title(self) -> None:
        """Must-F-01: REQUEST_VALIDATION_FAILED when title is missing."""
        factory = HypothesisFactory()
        payload = _make_valid_payload()
        del payload["title"]
        with pytest.raises(ValueError, match=ReasonCode.REQUEST_VALIDATION_FAILED.value):
            factory.from_proposed_event(
                event_payload=payload,
                identifier=_IDENTIFIER,
                trace=_TRACE,
                occurred_at=_NOW,
            )

    def test_rejects_missing_source_evidence(self) -> None:
        factory = HypothesisFactory()
        payload = _make_valid_payload()
        del payload["sourceEvidence"]
        with pytest.raises(ValueError, match=ReasonCode.REQUEST_VALIDATION_FAILED.value):
            factory.from_proposed_event(
                event_payload=payload,
                identifier=_IDENTIFIER,
                trace=_TRACE,
                occurred_at=_NOW,
            )

    def test_rejects_empty_source_evidence_list(self) -> None:
        factory = HypothesisFactory()
        payload = _make_valid_payload()
        payload["sourceEvidence"] = []
        with pytest.raises(ValueError, match=ReasonCode.REQUEST_VALIDATION_FAILED.value):
            factory.from_proposed_event(
                event_payload=payload,
                identifier=_IDENTIFIER,
                trace=_TRACE,
                occurred_at=_NOW,
            )

    def test_rejects_missing_skill_version(self) -> None:
        factory = HypothesisFactory()
        payload = _make_valid_payload()
        del payload["skillVersion"]
        with pytest.raises(ValueError, match=ReasonCode.REQUEST_VALIDATION_FAILED.value):
            factory.from_proposed_event(
                event_payload=payload,
                identifier=_IDENTIFIER,
                trace=_TRACE,
                occurred_at=_NOW,
            )

    def test_rejects_missing_instruction_profile_version(self) -> None:
        factory = HypothesisFactory()
        payload = _make_valid_payload()
        del payload["instructionProfileVersion"]
        with pytest.raises(ValueError, match=ReasonCode.REQUEST_VALIDATION_FAILED.value):
            factory.from_proposed_event(
                event_payload=payload,
                identifier=_IDENTIFIER,
                trace=_TRACE,
                occurred_at=_NOW,
            )

    def test_rejects_invalid_instrument_type(self) -> None:
        factory = HypothesisFactory()
        payload = _make_valid_payload()
        payload["instrumentType"] = "BOND"
        with pytest.raises(ValueError, match=ReasonCode.REQUEST_VALIDATION_FAILED.value):
            factory.from_proposed_event(
                event_payload=payload,
                identifier=_IDENTIFIER,
                trace=_TRACE,
                occurred_at=_NOW,
            )

    def test_stock_instrument_type_accepted(self) -> None:
        factory = HypothesisFactory()
        payload = _make_valid_payload()
        payload["instrumentType"] = "STOCK"
        hypothesis = factory.from_proposed_event(
            event_payload=payload,
            identifier=_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert hypothesis.instrument_type == InstrumentType.STOCK

    def test_optional_insider_risk_accepted(self) -> None:
        from domain.value_object.enums import InsiderRisk

        factory = HypothesisFactory()
        payload = _make_valid_payload()
        payload["insiderRisk"] = "low"
        hypothesis = factory.from_proposed_event(
            event_payload=payload,
            identifier=_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert hypothesis.insider_risk == InsiderRisk.LOW

    def test_optional_requires_compliance_review_accepted(self) -> None:
        factory = HypothesisFactory()
        payload = _make_valid_payload()
        payload["requiresComplianceReview"] = True
        hypothesis = factory.from_proposed_event(
            event_payload=payload,
            identifier=_IDENTIFIER,
            trace=_TRACE,
            occurred_at=_NOW,
        )
        assert hypothesis.requires_compliance_review is True
