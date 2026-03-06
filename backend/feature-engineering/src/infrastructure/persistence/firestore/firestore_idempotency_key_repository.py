"""Firestore implementation of IdempotencyKeyRepository."""

from __future__ import annotations

import datetime
from typing import Any, cast

from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore_v1 import Client
from google.cloud.firestore_v1.base_document import DocumentSnapshot

from domain.repository.idempotency_key_repository import IdempotencyKeyRepository, ReservationStatus
from infrastructure.error import InfrastructureDataFormatError

COLLECTION_NAME = "idempotency_keys"
TTL_DAYS = 30


class FirestoreIdempotencyKeyRepository(IdempotencyKeyRepository):
    """Firestore-backed repository for idempotency key management with short-lived leases."""

    def __init__(self, client: Client, service_name: str) -> None:
        self._client = client
        self._service_name = service_name

    def _document_identifier(self, identifier: str) -> str:
        """Build a service-scoped document ID to prevent cross-service collisions."""
        return f"{self._service_name}:{identifier}"

    def find(self, identifier: str) -> datetime.datetime | None:
        """Return processedAt only after the event has completed successfully."""
        snapshot = self._get_snapshot(identifier)
        if not snapshot.exists:
            return None
        data = snapshot.to_dict()
        if data is None:
            return None
        return _extract_processed_at(data)

    def reserve(
        self,
        identifier: str,
        leased_at: datetime.datetime,
        lease_expires_at: datetime.datetime,
        trace: str,
    ) -> ReservationStatus:
        """Acquire a short-lived processing lease or report the current state."""
        document_reference = self._document_reference(identifier)
        base_data: dict[str, Any] = {
            "identifier": identifier,
            "service": self._service_name,
            "trace": trace,
            "processedAt": None,
            "leaseExpiresAt": lease_expires_at,
            "expiresAt": leased_at + datetime.timedelta(days=TTL_DAYS),
            "updatedAt": leased_at,
        }

        try:
            document_reference.create(base_data)
            return ReservationStatus.ACQUIRED
        except AlreadyExists:
            snapshot = cast(DocumentSnapshot, document_reference.get())
            if not snapshot.exists:
                document_reference.set(base_data)
                return ReservationStatus.ACQUIRED

            data = snapshot.to_dict()
            if data is None:
                document_reference.set(base_data)
                return ReservationStatus.ACQUIRED

            processed_at = _extract_processed_at(data)
            if processed_at is not None:
                expires_at = _extract_optional_datetime(data, "expiresAt")
                if expires_at is None or expires_at > leased_at:
                    return ReservationStatus.PROCESSED

            lease_value = _extract_optional_datetime(data, "leaseExpiresAt")
            if lease_value is not None and lease_value > leased_at:
                return ReservationStatus.LEASED

            document_reference.set(base_data, merge=True)
            return ReservationStatus.ACQUIRED

    def persist(self, identifier: str, processed_at: datetime.datetime, trace: str) -> None:
        """Mark the event as processed after all durable work and publish steps succeed."""
        document_identifier = self._document_identifier(identifier)
        expires_at = processed_at + datetime.timedelta(days=TTL_DAYS)
        data: dict[str, Any] = {
            "identifier": identifier,
            "service": self._service_name,
            "processedAt": processed_at,
            "trace": trace,
            "leaseExpiresAt": None,
            "expiresAt": expires_at,
            "updatedAt": processed_at,
        }
        self._client.collection(COLLECTION_NAME).document(document_identifier).set(data, merge=True)

    def release(self, identifier: str, released_at: datetime.datetime) -> None:
        """Release the current lease so Pub/Sub redelivery can retry immediately."""
        document_reference = self._document_reference(identifier)
        snapshot = cast(DocumentSnapshot, document_reference.get())
        if not snapshot.exists:
            return
        document_reference.set(
            {
                "leaseExpiresAt": released_at,
                "updatedAt": released_at,
            },
            merge=True,
        )

    def terminate(self, identifier: str) -> None:
        """Delete the idempotency document."""
        self._document_reference(identifier).delete()

    def _document_reference(self, identifier: str):
        """Return the Firestore document reference for the identifier."""
        document_identifier = self._document_identifier(identifier)
        return self._client.collection(COLLECTION_NAME).document(document_identifier)

    def _get_snapshot(self, identifier: str) -> DocumentSnapshot:
        """Load the current document snapshot."""
        return cast(DocumentSnapshot, self._document_reference(identifier).get())


def _extract_processed_at(data: dict[str, Any]) -> datetime.datetime | None:
    """Extract a processedAt timestamp from a Firestore document."""
    processed_at = data.get("processedAt")
    if processed_at is None:
        return None
    if not isinstance(processed_at, datetime.datetime):
        raise InfrastructureDataFormatError(
            source=COLLECTION_NAME,
            detail="Failed to deserialize document: processedAt must be datetime",
            cause=TypeError("processedAt must be datetime"),
        )
    return processed_at


def _extract_optional_datetime(data: dict[str, Any], field_name: str) -> datetime.datetime | None:
    """Extract an optional datetime field from a Firestore document."""
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
