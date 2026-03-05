"""Firestore implementation of IdempotencyKeyRepository."""

from __future__ import annotations

import datetime
from typing import Any, cast

from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore_v1 import Client, transactional
from google.cloud.firestore_v1.base_document import DocumentSnapshot
from google.cloud.firestore_v1.transaction import Transaction

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
            # Attempt atomic reclaim of expired/stale documents using a
            # transaction so that concurrent consumers cannot both succeed.
            return self._try_atomic_reclaim(document_reference, data, now)

    def _try_atomic_reclaim(
        self, document_reference: Any, data: dict[str, Any], now: datetime.datetime
    ) -> bool:
        """Atomically reclaim an expired document inside a Firestore transaction.

        The transaction reads the existing document, checks expiration, then
        deletes and re-creates within the same transaction. If another consumer
        modifies the document concurrently, the transaction is retried (or
        aborted), guaranteeing at most one consumer succeeds.
        """
        transaction = self._client.transaction()

        @transactional
        def _reclaim_in_transaction(txn: Transaction) -> bool:
            snapshot = document_reference.get(transaction=txn)
            if not snapshot.exists:
                txn.set(document_reference, data)
                return True
            existing_data = snapshot.to_dict()
            if existing_data is None:
                txn.set(document_reference, data)
                return True
            expires_at = existing_data.get("expiresAt")
            if isinstance(expires_at, datetime.datetime) and expires_at <= now:
                # Overwrite the expired document atomically.
                txn.set(document_reference, data)
                return True
            return False

        try:
            return _reclaim_in_transaction(transaction)
        except Exception:
            return False

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
