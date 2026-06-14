"""HypothesisFactory."""

import datetime

from hypothesis_lab.domain.aggregates.hypothesis import Hypothesis
from hypothesis_lab.domain.enums.hypothesis_status import HypothesisStatus
from hypothesis_lab.domain.enums.insider_risk import InsiderRisk
from hypothesis_lab.domain.enums.instrument_type import InstrumentType
from hypothesis_lab.domain.identifiers import HypothesisIdentifier


class HypothesisFactory:
    """proposed イベントから Hypothesis 集約を作成するファクトリ。

    M-15: 必須フィールドが欠損している場合は ValueError を送出する。
    """

    @classmethod
    def from_proposed_event(cls, event_payload: dict) -> "Hypothesis":
        """proposed イベントの dict ペイロードから DRAFT 状態の Hypothesis を作成する。

        camelCase キー（AsyncAPI hypothesis.proposed イベント形式）を優先し、
        snake_case フォールバックをサポートする。

        M-15: 必須フィールド（title, source_evidence, skill_version, instruction_profile_version）が
        欠損している場合は ValueError を送出する。
        """
        raw_identifier = (
            event_payload.get("identifier")
            or event_payload.get("hypothesis")
        )
        title = event_payload.get("title")
        source_evidence = (
            event_payload.get("sourceEvidence")
            or event_payload.get("source_evidence")
            or []
        )
        skill_version = (
            event_payload.get("skillVersion")
            or event_payload.get("skill_version")
        )
        instruction_profile_version = (
            event_payload.get("instructionProfileVersion")
            or event_payload.get("instruction_profile_version")
        )
        symbol = event_payload.get("symbol")
        instrument_type_str = (
            event_payload.get("instrumentType")
            or event_payload.get("instrument_type")
        )
        insider_risk_str = (
            event_payload.get("insiderRisk")
            or event_payload.get("insider_risk")
        )
        updated_at_val = (
            event_payload.get("updatedAt")
            or event_payload.get("updated_at")
            or event_payload.get("occurredAt")
        )

        # Validate required fields
        if not title:
            raise ValueError("title は必須です（空文字列は不可）")
        if not source_evidence:
            raise ValueError("source_evidence は 1 件以上必須です")
        if not skill_version:
            raise ValueError("skill_version は必須です（空文字列は不可）")
        if not instruction_profile_version:
            raise ValueError("instruction_profile_version は必須です（空文字列は不可）")
        if not raw_identifier:
            raise ValueError("identifier は必須です")
        if not symbol:
            raise ValueError("symbol は必須です")
        if instrument_type_str is None:
            raise ValueError("instrumentType は必須です")

        # Resolve instrument_type
        if isinstance(instrument_type_str, InstrumentType):
            instrument_type = instrument_type_str
        else:
            instrument_type = InstrumentType(instrument_type_str)

        # Resolve insider_risk (optional)
        insider_risk: InsiderRisk | None = None
        if insider_risk_str is not None:
            if isinstance(insider_risk_str, InsiderRisk):
                insider_risk = insider_risk_str
            else:
                insider_risk = InsiderRisk(insider_risk_str)

        # Resolve updated_at
        if isinstance(updated_at_val, datetime.datetime):
            updated_at = updated_at_val
        elif isinstance(updated_at_val, str):
            updated_at = datetime.datetime.fromisoformat(updated_at_val)
        else:
            updated_at = datetime.datetime.now(tz=datetime.timezone.utc)

        return Hypothesis(
            identifier=HypothesisIdentifier(raw_identifier),
            symbol=symbol,
            instrument_type=instrument_type,
            status=HypothesisStatus.DRAFT,
            title=title,
            source_evidence=list(source_evidence),
            skill_version=skill_version,
            instruction_profile_version=instruction_profile_version,
            insider_risk=insider_risk,
            updated_at=updated_at,
        )
