"""Firestore implementation of IdempotencyKeyRepository."""

import datetime

from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore_v1 import Client as FirestoreClient
from google.cloud.firestore_v1.base_document import DocumentSnapshot

from signal_generator.domain.repositories.idempotency_key_repository import (
    IdempotencyKeyRepository,
)

_COLLECTION_NAME = "idempotency_keys"
_SERVICE_NAME = "signal-generator"
_TTL_DAYS = 30


class FirestoreIdempotencyKeyRepository(IdempotencyKeyRepository):
    """idempotency_keys コレクションを使った冪等性キーリポジトリ。

    Firestore TTL ポリシーにより expiresAt 経過後にドキュメントが自動削除される。
    """

    def __init__(self, firestore_client: FirestoreClient) -> None:
        self._firestore_client = firestore_client

    def find(self, identifier: str) -> bool:
        document_reference = self._firestore_client.collection(_COLLECTION_NAME).document(identifier)
        document_snapshot: DocumentSnapshot = document_reference.get()  # type: ignore[assignment]
        return bool(document_snapshot.exists)

    def persist(
        self,
        identifier: str,
        processed_at: datetime.datetime,
        trace: str,
    ) -> bool:
        expires_at = processed_at + datetime.timedelta(days=_TTL_DAYS)
        document_data = {
            "identifier": identifier,
            "service": _SERVICE_NAME,
            "processedAt": processed_at,
            "trace": trace,
            "expiresAt": expires_at,
        }
        document_reference = self._firestore_client.collection(_COLLECTION_NAME).document(identifier)
        try:
            document_reference.create(document_data)
            return True
        except AlreadyExists:
            return False

    def terminate(self, identifier: str) -> None:
        document_reference = self._firestore_client.collection(_COLLECTION_NAME).document(identifier)
        document_reference.delete()
