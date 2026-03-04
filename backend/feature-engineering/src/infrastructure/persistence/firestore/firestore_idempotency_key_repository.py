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

    def _document_identifier(self, identifier: str) -> str:
        """Build a service-scoped document ID to prevent cross-service collisions."""
        return f"{self._service_name}:{identifier}"

    def find(self, identifier: str) -> datetime.datetime | None:
        document_identifier = self._document_identifier(identifier)
        snapshot: DocumentSnapshot = self._client.collection(COLLECTION_NAME).document(document_identifier).get()  # type: ignore[assignment]
        if not snapshot.exists:
            return None
        data = snapshot.to_dict()
        if data is None:
            return None
        processed_at: datetime.datetime = data["processedAt"]
        return processed_at

    def persist(self, identifier: str, processed_at: datetime.datetime) -> None:
        document_identifier = self._document_identifier(identifier)
        expires_at = processed_at + datetime.timedelta(days=TTL_DAYS)
        data: dict[str, Any] = {
            "identifier": identifier,
            "service": self._service_name,
            "processedAt": processed_at,
            "expiresAt": expires_at,
        }
        self._client.collection(COLLECTION_NAME).document(document_identifier).set(data)

    def terminate(self, identifier: str) -> None:
        document_identifier = self._document_identifier(identifier)
        self._client.collection(COLLECTION_NAME).document(document_identifier).delete()
