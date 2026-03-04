"""Firestore implementation of IdempotencyKeyRepository."""

import datetime

from google.cloud.firestore_v1 import Client as FirestoreClient

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
        document_reference = self._firestore_client.collection(
            _COLLECTION_NAME
        ).document(identifier)
        document_snapshot = document_reference.get()
        return document_snapshot.exists

    def persist(
        self,
        identifier: str,
        processed_at: datetime.datetime,
        trace: str | None = None,
    ) -> None:
        expires_at = processed_at + datetime.timedelta(days=_TTL_DAYS)
        document_data = {
            "identifier": identifier,
            "service": _SERVICE_NAME,
            "processedAt": processed_at,
            "trace": trace if trace is not None else identifier,
            "expiresAt": expires_at,
        }
        document_reference = self._firestore_client.collection(
            _COLLECTION_NAME
        ).document(identifier)
        document_reference.set(document_data)

    def terminate(self, identifier: str) -> None:
        document_reference = self._firestore_client.collection(
            _COLLECTION_NAME
        ).document(identifier)
        document_reference.delete()
