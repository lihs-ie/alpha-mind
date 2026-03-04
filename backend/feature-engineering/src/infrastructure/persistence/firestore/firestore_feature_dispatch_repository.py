"""Firestore implementation of FeatureDispatchRepository."""

from __future__ import annotations

from typing import Any

from google.cloud.firestore_v1 import Client
from google.cloud.firestore_v1.base_document import DocumentSnapshot

from domain.model.feature_dispatch import FeatureDispatch
from domain.repository.feature_dispatch_repository import FeatureDispatchRepository
from domain.value_object.dispatch_decision import DispatchDecision
from domain.value_object.enums import DispatchStatus, PublishedEventType, ReasonCode

COLLECTION_NAME = "feature_dispatches"


class FirestoreFeatureDispatchRepository(FeatureDispatchRepository):
    """Firestore-backed repository for FeatureDispatch aggregates."""

    def __init__(self, client: Client) -> None:
        self._client = client

    def find(self, identifier: str) -> FeatureDispatch | None:
        snapshot: DocumentSnapshot = self._client.collection(COLLECTION_NAME).document(identifier).get()  # type: ignore[assignment]
        if not snapshot.exists:
            return None
        data = snapshot.to_dict()
        if data is None:
            return None
        return _deserialize(data)

    def persist(self, feature_dispatch: FeatureDispatch) -> None:
        data = _serialize(feature_dispatch)
        self._client.collection(COLLECTION_NAME).document(feature_dispatch.identifier).set(data)

    def terminate(self, identifier: str) -> None:
        self._client.collection(COLLECTION_NAME).document(identifier).delete()


def _serialize(dispatch: FeatureDispatch) -> dict[str, Any]:
    decision = dispatch.dispatch_decision
    return {
        "identifier": dispatch.identifier,
        "dispatchStatus": dispatch.dispatch_status.value,
        "trace": dispatch.trace,
        "dispatchDecision": {
            "dispatchStatus": decision.dispatch_status.value,
            "publishedEvent": decision.published_event.value if decision.published_event is not None else None,
            "reasonCode": decision.reason_code.value if decision.reason_code is not None else None,
        },
        "processedAt": dispatch.processed_at,
    }


def _deserialize(data: dict[str, Any]) -> FeatureDispatch:
    decision_data = data["dispatchDecision"]

    published_event: PublishedEventType | None = None
    if decision_data["publishedEvent"] is not None:
        published_event = PublishedEventType(decision_data["publishedEvent"])

    reason_code: ReasonCode | None = None
    if decision_data["reasonCode"] is not None:
        reason_code = ReasonCode(decision_data["reasonCode"])

    return FeatureDispatch(
        identifier=data["identifier"],
        dispatch_status=DispatchStatus(data["dispatchStatus"]),
        trace=data["trace"],
        dispatch_decision=DispatchDecision(
            dispatch_status=DispatchStatus(decision_data["dispatchStatus"]),
            published_event=published_event,
            reason_code=reason_code,
        ),
        processed_at=data.get("processedAt"),
    )
