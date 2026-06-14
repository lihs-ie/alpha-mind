"""HypothesisFactory — creates Hypothesis aggregates from proposed events."""

from __future__ import annotations

import datetime

from domain.model.hypothesis import Hypothesis
from domain.value_object.enums import HypothesisStatus, InsiderRisk, InstrumentType, ReasonCode


class HypothesisFactory:
    """Factory that constructs Hypothesis aggregates from hypothesis.proposed event payloads.

    Must-F-01: validates required fields (title, source_evidence, skill_version,
    instruction_profile_version) and sets status=draft.
    """

    def from_proposed_event(
        self,
        event_payload: dict[str, object],
        identifier: str,
        trace: str,
        occurred_at: datetime.datetime,
    ) -> Hypothesis:
        """Create a Hypothesis with status=draft from a hypothesis.proposed event payload.

        Args:
            event_payload: Raw event payload dict.
            identifier: Pre-generated ULID identifier for the new Hypothesis.
            trace: Trace ULID for the event envelope.
            occurred_at: Event occurrence timestamp.

        Returns:
            Hypothesis with status=draft.

        Raises:
            ValueError: If any required payload field is missing or empty, with
                        reason_code REQUEST_VALIDATION_FAILED embedded in the message.
        """
        required_fields = [
            "title",
            "sourceEvidence",
            "skillVersion",
            "instructionProfileVersion",
            "symbol",
            "instrumentType",
        ]
        for field_name in required_fields:
            value = event_payload.get(field_name)
            if value is None or value == "" or value == []:
                raise ValueError(
                    f"{ReasonCode.REQUEST_VALIDATION_FAILED.value}: "
                    f"required field '{field_name}' is missing or empty in hypothesis.proposed payload"
                )

        title = str(event_payload["title"])
        source_evidence_raw = event_payload["sourceEvidence"]
        if not isinstance(source_evidence_raw, list) or len(source_evidence_raw) == 0:
            raise ValueError(f"{ReasonCode.REQUEST_VALIDATION_FAILED.value}: sourceEvidence must be a non-empty list")
        source_evidence: list[str] = [str(item) for item in source_evidence_raw]

        skill_version = str(event_payload["skillVersion"])
        instruction_profile_version = str(event_payload["instructionProfileVersion"])
        symbol = str(event_payload["symbol"])

        instrument_type_raw = str(event_payload["instrumentType"])
        try:
            instrument_type = InstrumentType(instrument_type_raw)
        except ValueError as error:
            raise ValueError(
                f"{ReasonCode.REQUEST_VALIDATION_FAILED.value}: "
                f"instrumentType '{instrument_type_raw}' is not a valid InstrumentType"
            ) from error

        # Optional compliance fields
        insider_risk: InsiderRisk | None = None
        insider_risk_raw = event_payload.get("insiderRisk")
        if insider_risk_raw is not None:
            try:
                insider_risk = InsiderRisk(str(insider_risk_raw))
            except ValueError as error:
                raise ValueError(
                    f"{ReasonCode.REQUEST_VALIDATION_FAILED.value}: "
                    f"insiderRisk '{insider_risk_raw}' is not a valid InsiderRisk"
                ) from error

        requires_compliance_review: bool | None = None
        if "requiresComplianceReview" in event_payload:
            requires_compliance_review = bool(event_payload["requiresComplianceReview"])

        return Hypothesis(
            identifier=identifier,
            symbol=symbol,
            instrument_type=instrument_type,
            status=HypothesisStatus.DRAFT,
            title=title,
            source_evidence=source_evidence,
            skill_version=skill_version,
            instruction_profile_version=instruction_profile_version,
            updated_at=occurred_at,
            insider_risk=insider_risk,
            requires_compliance_review=requires_compliance_review,
        )
