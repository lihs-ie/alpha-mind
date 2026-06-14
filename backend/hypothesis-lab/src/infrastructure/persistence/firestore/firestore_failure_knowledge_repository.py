"""Firestore implementation of FailureKnowledgeRepository."""

from __future__ import annotations

import datetime
from typing import Any, cast

from google.cloud.firestore_v1 import Client, FieldFilter
from google.cloud.firestore_v1.base_document import DocumentSnapshot

from domain.repository.failure_knowledge_repository import FailureKnowledgeRepository
from domain.value_object.enums import ReasonCode
from domain.value_object.failure_summary import FailureSummary
from infrastructure.error import InfrastructureDataFormatError

COLLECTION_NAME = "failure_knowledge"

FailureKnowledgeIdentifier = str


class FirestoreFailureKnowledgeRepository(FailureKnowledgeRepository):
    """Firestore-backed repository for FailureSummary records.

    Documents are stored with an auto-generated identifier (ULID via python-ulid).
    The ABC persist() stores with a generated ID; persist_with_metadata() allows
    callers to supply the full envelope context.
    """

    def __init__(self, client: Client) -> None:
        self._client = client

    def find(self, identifier: FailureKnowledgeIdentifier) -> FailureSummary | None:
        snapshot = cast(DocumentSnapshot, self._client.collection(COLLECTION_NAME).document(identifier).get())
        if not snapshot.exists:
            return None
        data = snapshot.to_dict()
        if data is None:
            return None
        return _deserialize(data)

    def find_by_reason_code(self, reason_code: ReasonCode) -> list[FailureSummary]:
        query = self._client.collection(COLLECTION_NAME).where(
            filter=FieldFilter("reasonCode", "==", reason_code.value)
        )
        return [_deserialize(data) for document in query.stream() if (data := document.to_dict()) is not None]

    def search(self, criteria: dict[str, Any] | None = None) -> list[FailureSummary]:
        collection_reference = self._client.collection(COLLECTION_NAME)
        return [
            _deserialize(data) for document in collection_reference.stream() if (data := document.to_dict()) is not None
        ]

    def persist(self, failure_summary: FailureSummary) -> None:
        """Persist a FailureSummary with an auto-generated document identifier."""
        import ulid

        identifier = str(ulid.ULID())
        now = datetime.datetime.now(tz=datetime.UTC)
        self.persist_with_metadata(
            identifier=identifier,
            hypothesis_identifier="",
            failure_summary=failure_summary,
            trace="",
            created_at=now,
        )

    def persist_with_metadata(
        self,
        identifier: FailureKnowledgeIdentifier,
        hypothesis_identifier: str,
        failure_summary: FailureSummary,
        trace: str,
        created_at: datetime.datetime,
    ) -> None:
        """Persist a FailureSummary with full envelope metadata."""
        data: dict[str, Any] = {
            "identifier": identifier,
            "hypothesis": hypothesis_identifier,
            "reasonCode": failure_summary.reason_code.value,
            "markdownSummary": failure_summary.markdown_summary,
            "createdAt": created_at,
            "trace": trace,
        }
        self._client.collection(COLLECTION_NAME).document(identifier).set(data)

    def terminate(self, identifier: FailureKnowledgeIdentifier) -> None:
        self._client.collection(COLLECTION_NAME).document(identifier).delete()


def _deserialize(data: dict[str, Any]) -> FailureSummary:
    """Reconstruct FailureSummary from Firestore document."""
    try:
        return FailureSummary(
            reason_code=ReasonCode(data["reasonCode"]),
            markdown_summary=data["markdownSummary"],
        )
    except (KeyError, ValueError) as error:
        raise InfrastructureDataFormatError(
            source=COLLECTION_NAME,
            detail=f"Failed to deserialize document: {error}",
            cause=error,
        ) from error
