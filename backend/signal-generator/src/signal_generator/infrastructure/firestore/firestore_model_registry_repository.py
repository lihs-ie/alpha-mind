"""Firestore implementation of ModelRegistryRepository."""

from typing import Any

from google.cloud.firestore_v1 import Client as FirestoreClient
from google.cloud.firestore_v1 import Query
from google.cloud.firestore_v1.base_document import DocumentSnapshot
from google.cloud.firestore_v1.base_query import BaseQuery

from signal_generator.domain.enums.model_status import ModelStatus
from signal_generator.domain.repositories.model_registry_repository import (
    ModelRegistryRepository,
)
from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot

_COLLECTION_NAME = "model_registry"


class FirestoreModelRegistryRepository(ModelRegistryRepository):
    """model_registry コレクションへの読み取り専用アクセス実装。"""

    def __init__(self, firestore_client: FirestoreClient) -> None:
        self._firestore_client = firestore_client

    def find_by_status(self, status: ModelStatus) -> ModelSnapshot | None:
        query = (
            self._firestore_client.collection(_COLLECTION_NAME)
            .where("status", "==", status.value)
            .order_by("createdAt", direction=Query.DESCENDING)
        )
        documents = list(query.limit(1).stream())
        if not documents:
            return None
        return _to_model_snapshot(documents[0].to_dict())

    def find(self, model_version: str) -> ModelSnapshot | None:
        document_reference = self._firestore_client.collection(_COLLECTION_NAME).document(model_version)
        document_snapshot: DocumentSnapshot = document_reference.get()  # type: ignore[assignment]
        if not document_snapshot.exists:
            return None
        return _to_model_snapshot(document_snapshot.to_dict())

    def search(self, criteria: dict[str, object]) -> list[ModelSnapshot]:
        query: BaseQuery = self._firestore_client.collection(_COLLECTION_NAME)  # type: ignore[assignment]
        for field_name, value in criteria.items():
            query = query.where(field_name, "==", value)
        return [
            _to_model_snapshot(document.to_dict())
            for document in query.stream()  # type: ignore[union-attr]
        ]


def _to_model_snapshot(document_data: dict[str, Any] | None) -> ModelSnapshot:
    """Firestore ドキュメントを ModelSnapshot に変換する。"""
    if document_data is None:
        raise ValueError("document_data must not be None")

    # decidedAt は approved/rejected 時のみ存在する
    decided_at = document_data.get("decidedAt")
    status = ModelStatus(document_data["status"])
    approved_at = decided_at if status == ModelStatus.APPROVED else None

    return ModelSnapshot(
        model_version=document_data["modelVersion"],
        status=status,
        approved_at=approved_at,
    )
