"""Firestore implementation of IdempotencyKeyRepository."""

from __future__ import annotations

import datetime
from typing import Any, cast

from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore_v1 import Client
from google.cloud.firestore_v1.base_document import DocumentSnapshot

from domain.repository.idempotency_key_repository import IdempotencyKeyRepository
from infrastructure.error import InfrastructureDataFormatError

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

    def reserve(self, identifier: str, trace: str) -> bool:
        document_identifier = self._document_identifier(identifier)
        now = datetime.datetime.now(tz=datetime.UTC)
        expires_at = now + datetime.timedelta(days=TTL_DAYS)
        data: dict[str, Any] = {
            "identifier": identifier,
            "service": self._service_name,
            "reservedAt": now,
            "trace": trace,
            "expiresAt": expires_at,
            "status": "reserved",
        }
        document_reference = self._client.collection(COLLECTION_NAME).document(document_identifier)
        try:
            document_reference.create(data)
            return True
        except AlreadyExists:
            # Check if the existing document is expired or a stale reservation.
            # If so, delete it and retry the reservation.
            if self._is_reclaimable(document_reference, now):
                document_reference.delete()
                try:
                    document_reference.create(data)
                    return True
                except AlreadyExists:
                    return False
            return False

    def _is_reclaimable(self, document_reference: Any, now: datetime.datetime) -> bool:
        """Check if an existing document is expired and can be reclaimed."""
        snapshot = cast(DocumentSnapshot, document_reference.get())
        if not snapshot.exists:
            return True
        data = snapshot.to_dict()
        if data is None:
            return True
        expires_at = data.get("expiresAt")
        return isinstance(expires_at, datetime.datetime) and expires_at <= now

    def find(self, identifier: str) -> datetime.datetime | None:
        document_identifier = self._document_identifier(identifier)
        snapshot = cast(DocumentSnapshot, self._client.collection(COLLECTION_NAME).document(document_identifier).get())
        if not snapshot.exists:
            return None
        data = snapshot.to_dict()
        if data is None:
            return None

        # Documents in "reserved" status have no processedAt yet;
        # they represent in-flight processing, not completed events.
        if data.get("status") == "reserved":
            return None

        now = datetime.datetime.now(datetime.UTC)
        expires_at = data.get("expiresAt")
        if isinstance(expires_at, datetime.datetime) and expires_at <= now:
            return None

        try:
            processed_at = data["processedAt"]
            if not isinstance(processed_at, datetime.datetime):
                raise TypeError("processedAt must be datetime")
            return processed_at
        except (KeyError, TypeError) as error:
            raise InfrastructureDataFormatError(
                source=COLLECTION_NAME,
                detail=f"Failed to deserialize document: {error}",
                cause=error,
            ) from error

    def persist(self, identifier: str, processed_at: datetime.datetime, trace: str) -> None:
        document_identifier = self._document_identifier(identifier)
        expires_at = processed_at + datetime.timedelta(days=TTL_DAYS)
        data: dict[str, Any] = {
            "identifier": identifier,
            "service": self._service_name,
            "processedAt": processed_at,
            "trace": trace,
            "expiresAt": expires_at,
            "updatedAt": processed_at,
        }
        self._client.collection(COLLECTION_NAME).document(document_identifier).set(data)

    def terminate(self, identifier: str) -> None:
        document_identifier = self._document_identifier(identifier)
        self._client.collection(COLLECTION_NAME).document(document_identifier).delete()
