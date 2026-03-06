"""Firestore implementation of ModelRegistryRepository."""

from typing import Any, cast

from google.cloud.firestore_v1 import Client as FirestoreClient
from google.cloud.firestore_v1 import Query
from google.cloud.firestore_v1.base_document import DocumentSnapshot

from signal_generator.domain.enums.degradation_flag import DegradationFlag
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
        document_snapshot = cast(DocumentSnapshot, document_reference.get())
        if not document_snapshot.exists:
            return None
        return _to_model_snapshot(document_snapshot.to_dict())

    def search(self, criteria: dict[str, object], limit: int = 100) -> list[ModelSnapshot]:
        collection = self._firestore_client.collection(_COLLECTION_NAME)
        if not criteria:
            return [_to_model_snapshot(document.to_dict()) for document in collection.limit(limit).stream()]
        items = list(criteria.items())
        query: Query = collection.where(items[0][0], "==", items[0][1])
        for field_name, value in items[1:]:
            query = query.where(field_name, "==", value)
        return [_to_model_snapshot(document.to_dict()) for document in query.limit(limit).stream()]


def _to_model_snapshot(document_data: dict[str, Any] | None) -> ModelSnapshot:
    """Firestore ドキュメントを ModelSnapshot に変換する。"""
    if document_data is None:
        raise ValueError("document_data must not be None")

    # decidedAt は approved/rejected 時のみ存在する
    decided_at = document_data.get("decidedAt")
    status = ModelStatus(document_data["status"])
    approved_at = decided_at if status == ModelStatus.APPROVED else None

    # 診断フィールドの読み取り (なければデフォルト)
    degradation_flag_raw = document_data.get("degradationFlag")
    degradation_flag = DegradationFlag(degradation_flag_raw) if degradation_flag_raw else DegradationFlag.NORMAL
    cost_adjusted_return = document_data.get("costAdjustedReturn")
    slippage_adjusted_sharpe = document_data.get("slippageAdjustedSharpe")

    return ModelSnapshot(
        model_version=document_data["modelVersion"],
        status=status,
        approved_at=approved_at,
        degradation_flag=degradation_flag,
        cost_adjusted_return=cost_adjusted_return,
        slippage_adjusted_sharpe=slippage_adjusted_sharpe,
    )
