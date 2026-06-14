"""Firestore implementation of HypothesisRepository."""

from __future__ import annotations

from typing import Any, cast

from google.cloud.firestore_v1 import Client, FieldFilter
from google.cloud.firestore_v1.base_document import DocumentSnapshot

from domain.model.hypothesis import Hypothesis
from domain.repository.hypothesis_repository import HypothesisRepository
from domain.value_object.demo_window import DemoWindow
from domain.value_object.enums import (
    HypothesisStatus,
    InsiderRisk,
    InstrumentType,
    PromotionMode,
    ReasonCode,
)
from domain.value_object.failure_summary import FailureSummary
from domain.value_object.performance_metrics import PerformanceMetrics
from infrastructure.error import InfrastructureDataFormatError

COLLECTION_NAME = "hypothesis_registry"

HypothesisIdentifier = str


class FirestoreHypothesisRepository(HypothesisRepository):
    """Firestore-backed repository for Hypothesis aggregates."""

    def __init__(self, client: Client) -> None:
        self._client = client

    def find(self, identifier: HypothesisIdentifier) -> Hypothesis | None:
        snapshot = cast(DocumentSnapshot, self._client.collection(COLLECTION_NAME).document(identifier).get())
        if not snapshot.exists:
            return None
        data = snapshot.to_dict()
        if data is None:
            return None
        return _deserialize(data)

    def find_by_status(self, status: HypothesisStatus) -> list[Hypothesis]:
        query = self._client.collection(COLLECTION_NAME).where(filter=FieldFilter("status", "==", status.value))
        return [_deserialize(data) for document in query.stream() if (data := document.to_dict()) is not None]

    def search(self, criteria: dict[str, Any] | None = None) -> list[Hypothesis]:
        collection_reference = self._client.collection(COLLECTION_NAME)
        return [
            _deserialize(data) for document in collection_reference.stream() if (data := document.to_dict()) is not None
        ]

    def persist(self, hypothesis: Hypothesis) -> None:
        data = _serialize(hypothesis)
        self._client.collection(COLLECTION_NAME).document(hypothesis.identifier).set(data)

    def terminate(self, identifier: HypothesisIdentifier) -> None:
        self._client.collection(COLLECTION_NAME).document(identifier).delete()


def _serialize(hypothesis: Hypothesis) -> dict[str, Any]:
    """Convert Hypothesis aggregate to Firestore document."""
    failure_summary_value: str | None = None
    if hypothesis.latest_failure_summary is not None:
        failure_summary_value = hypothesis.latest_failure_summary.markdown_summary

    return {
        "identifier": hypothesis.identifier,
        "symbol": hypothesis.symbol,
        "instrumentType": hypothesis.instrument_type.value,
        "status": hypothesis.status.value,
        "title": hypothesis.title,
        "sourceEvidence": hypothesis.source_evidence,
        "skillVersion": hypothesis.skill_version,
        "instructionProfileVersion": hypothesis.instruction_profile_version,
        "updatedAt": hypothesis.updated_at,
        "insiderRisk": hypothesis.insider_risk.value if hypothesis.insider_risk is not None else None,
        "requiresComplianceReview": hypothesis.requires_compliance_review,
        "mnpiSelfDeclared": hypothesis.mnpi_self_declared,
        "autoPromotionEligible": hypothesis.auto_promotion_eligible,
        "promotionMode": hypothesis.promotion_mode.value if hypothesis.promotion_mode is not None else None,
        "latestFailureSummary": failure_summary_value,
        "trace": "",
    }


def _deserialize(data: dict[str, Any]) -> Hypothesis:
    """Reconstruct Hypothesis aggregate from Firestore document."""
    try:
        insider_risk: InsiderRisk | None = None
        if data.get("insiderRisk") is not None:
            insider_risk = InsiderRisk(data["insiderRisk"])

        promotion_mode: PromotionMode | None = None
        if data.get("promotionMode") is not None:
            promotion_mode = PromotionMode(data["promotionMode"])

        latest_failure_summary: FailureSummary | None = None
        if data.get("latestFailureSummary") is not None:
            latest_failure_summary = FailureSummary(
                reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
                markdown_summary=data["latestFailureSummary"],
            )

        return Hypothesis(
            identifier=data["identifier"],
            symbol=data["symbol"],
            instrument_type=InstrumentType(data["instrumentType"]),
            status=HypothesisStatus(data["status"]),
            title=data["title"],
            source_evidence=list(data["sourceEvidence"]),
            skill_version=data["skillVersion"],
            instruction_profile_version=data["instructionProfileVersion"],
            updated_at=data["updatedAt"],
            insider_risk=insider_risk,
            requires_compliance_review=data.get("requiresComplianceReview"),
            mnpi_self_declared=data.get("mnpiSelfDeclared"),
            auto_promotion_eligible=data.get("autoPromotionEligible"),
            promotion_mode=promotion_mode,
            latest_failure_summary=latest_failure_summary,
        )
    except (KeyError, ValueError) as error:
        raise InfrastructureDataFormatError(
            source=COLLECTION_NAME,
            detail=f"Failed to deserialize document: {error}",
            cause=error,
        ) from error


def _deserialize_performance_metrics(data: dict[str, Any]) -> PerformanceMetrics:
    """Reconstruct PerformanceMetrics from a Firestore sub-document."""
    return PerformanceMetrics(
        cost_adjusted_return=float(data["costAdjustedReturn"]),
        dsr=float(data["dsr"]),
        pbo=float(data["pbo"]),
    )


def _deserialize_demo_window(data: dict[str, Any]) -> DemoWindow:
    """Reconstruct DemoWindow from a Firestore sub-document."""
    return DemoWindow(
        started_at=data["startedAt"],
        ended_at=data["endedAt"],
        demo_period_days=int(data["demoPeriodDays"]),
    )
