"""Firestore implementation of FeatureDispatchOutboxRepository."""

from __future__ import annotations

import datetime
from typing import Any, cast

from google.cloud.firestore_v1 import Client
from google.cloud.firestore_v1.base_document import DocumentSnapshot

from domain.model.feature_dispatch_outbox import FeatureDispatchOutbox, OutboxStatus
from domain.repository.feature_dispatch_outbox_repository import FeatureDispatchOutboxRepository
from domain.value_object.enums import PublishedEventType
from infrastructure.error import InfrastructureDataFormatError

COLLECTION_NAME = "feature_dispatch_outbox"


class FirestoreFeatureDispatchOutboxRepository(FeatureDispatchOutboxRepository):
    """Firestore-backed repository for durable dispatch outbox entries."""

    def __init__(self, client: Client) -> None:
        self._client = client

    def find(self, identifier: str) -> FeatureDispatchOutbox | None:
        snapshot = cast(DocumentSnapshot, self._client.collection(COLLECTION_NAME).document(identifier).get())
        if not snapshot.exists:
            return None
        data = snapshot.to_dict()
        if data is None:
            return None
        return _deserialize(data)

    def persist(self, outbox_entry: FeatureDispatchOutbox) -> None:
        self._client.collection(COLLECTION_NAME).document(outbox_entry.identifier).set(_serialize(outbox_entry))

    def mark_published(self, identifier: str, published_at: datetime.datetime) -> None:
        snapshot = cast(DocumentSnapshot, self._client.collection(COLLECTION_NAME).document(identifier).get())
        if not snapshot.exists:
            return
        data = snapshot.to_dict()
        if data is None:
            return
        entry = _deserialize(data).mark_published(published_at)
        self.persist(entry)

    def terminate(self, identifier: str) -> None:
        self._client.collection(COLLECTION_NAME).document(identifier).delete()


def _serialize(outbox_entry: FeatureDispatchOutbox) -> dict[str, Any]:
    return {
        "identifier": outbox_entry.identifier,
        "trace": outbox_entry.trace,
        "publishedEvent": outbox_entry.published_event.value,
        "status": outbox_entry.status.value,
        "createdAt": outbox_entry.created_at,
        "publishedAt": outbox_entry.published_at,
        "updatedAt": outbox_entry.published_at or outbox_entry.created_at,
    }


def _deserialize(data: dict[str, Any]) -> FeatureDispatchOutbox:
    try:
        created_at = _require_datetime(data, "createdAt")
        published_at = _extract_optional_datetime(data, "publishedAt")
        return FeatureDispatchOutbox(
            identifier=data["identifier"],
            trace=data["trace"],
            published_event=PublishedEventType(data["publishedEvent"]),
            status=OutboxStatus(data["status"]),
            created_at=created_at,
            published_at=published_at,
        )
    except (KeyError, ValueError) as error:
        raise InfrastructureDataFormatError(
            source=COLLECTION_NAME,
            detail=f"Failed to deserialize document: {error}",
            cause=error,
        ) from error


def _require_datetime(data: dict[str, Any], field_name: str) -> datetime.datetime:
    value = data.get(field_name)
    if not isinstance(value, datetime.datetime):
        raise InfrastructureDataFormatError(
            source=COLLECTION_NAME,
            detail=f"Failed to deserialize document: {field_name} must be datetime",
            cause=TypeError(f"{field_name} must be datetime"),
        )
    return value


def _extract_optional_datetime(data: dict[str, Any], field_name: str) -> datetime.datetime | None:
    value = data.get(field_name)
    if value is None:
        return None
    if not isinstance(value, datetime.datetime):
        raise InfrastructureDataFormatError(
            source=COLLECTION_NAME,
            detail=f"Failed to deserialize document: {field_name} must be datetime",
            cause=TypeError(f"{field_name} must be datetime"),
        )
    return value
