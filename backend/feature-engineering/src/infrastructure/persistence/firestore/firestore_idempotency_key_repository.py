"""Firestore implementation of IdempotencyKeyRepository."""

from __future__ import annotations

import datetime
from typing import Any

from google.cloud.firestore_v1 import Client
from google.cloud.firestore_v1.base_document import DocumentSnapshot

from domain.repository.idempotency_key_repository import IdempotencyKeyRepository

COLLECTION_NAME = "idempotency_keys"
TTL_DAYS = 30


class FirestoreIdempotencyKeyRepository(IdempotencyKeyRepository):
    """Firestore-backed repository for idempotency key management."""

    def __init__(self, client: Client, service_name: str) -> None:
        self._client = client
        self._service_name = service_name

    def find(self, identifier: str) -> datetime.datetime | None:
        snapshot: DocumentSnapshot = self._client.collection(COLLECTION_NAME).document(identifier).get()  # type: ignore[assignment]
        if not snapshot.exists:
            return None
        data = snapshot.to_dict()
        if data is None:
            return None
        processed_at: datetime.datetime = data["processedAt"]
        return processed_at

    def persist(self, identifier: str, processed_at: datetime.datetime) -> None:
        expires_at = processed_at + datetime.timedelta(days=TTL_DAYS)
        data: dict[str, Any] = {
            "identifier": identifier,
            "service": self._service_name,
            "processedAt": processed_at,
            "expiresAt": expires_at,
        }
        self._client.collection(COLLECTION_NAME).document(identifier).set(data)

    def terminate(self, identifier: str) -> None:
        self._client.collection(COLLECTION_NAME).document(identifier).delete()
