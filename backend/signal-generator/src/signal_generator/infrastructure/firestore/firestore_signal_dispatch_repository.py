"""Firestore implementation of SignalDispatchRepository."""

import datetime
from typing import Any, cast

from google.cloud.firestore_v1 import Client as FirestoreClient
from google.cloud.firestore_v1.base_document import DocumentSnapshot

from signal_generator.domain.aggregates.signal_dispatch import SignalDispatch
from signal_generator.domain.enums.dispatch_status import DispatchStatus
from signal_generator.domain.enums.event_type import EventType
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.repositories.signal_dispatch_repository import (
    SignalDispatchRepository,
)

_COLLECTION_NAME = "idempotency_keys"
_SERVICE_NAME = "signal-generator"
_TTL_DAYS = 30


class FirestoreSignalDispatchRepository(SignalDispatchRepository):
    """idempotency_keys コレクションを使った SignalDispatch 永続化リポジトリ。"""

    def __init__(self, firestore_client: FirestoreClient) -> None:
        self._firestore_client = firestore_client

    def find(self, identifier: str) -> SignalDispatch | None:
        for document_identifier in (_document_identifier(identifier), identifier):
            document_reference = self._firestore_client.collection(_COLLECTION_NAME).document(document_identifier)
            document_snapshot = cast(DocumentSnapshot, document_reference.get())
            if document_snapshot.exists:
                return _to_signal_dispatch(document_snapshot.to_dict())
        return None

    def persist(self, signal_dispatch: SignalDispatch) -> None:
        document_data = _to_document_data(signal_dispatch)
        document_reference = self._firestore_client.collection(_COLLECTION_NAME).document(
            _document_identifier(signal_dispatch.identifier)
        )
        document_reference.set(document_data, merge=True)

    def terminate(self, identifier: str) -> None:
        document_reference = self._firestore_client.collection(_COLLECTION_NAME).document(_document_identifier(identifier))
        document_reference.delete()


def _to_document_data(signal_dispatch: SignalDispatch) -> dict[str, Any]:
    """SignalDispatch 集約を Firestore ドキュメントデータに変換する。"""
    updated_at = signal_dispatch.processed_at or datetime.datetime.now(datetime.UTC)
    document_data: dict[str, Any] = {
        "identifier": signal_dispatch.identifier,
        "service": _SERVICE_NAME,
        "trace": signal_dispatch.trace,
        "dispatchStatus": signal_dispatch.dispatch_status.value,
        "processedAt": signal_dispatch.processed_at,
        "updatedAt": updated_at,
        "expiresAt": updated_at + datetime.timedelta(days=_TTL_DAYS),
    }
    if signal_dispatch.published_event is not None:
        document_data["publishedEvent"] = signal_dispatch.published_event.value
    if signal_dispatch.reason_code is not None:
        document_data["reasonCode"] = signal_dispatch.reason_code.value
    return document_data


def _to_signal_dispatch(document_data: dict[str, Any] | None) -> SignalDispatch:
    """Firestore ドキュメントを SignalDispatch 集約に変換する。"""
    if document_data is None:
        raise ValueError("document_data must not be None")

    identifier = document_data["identifier"]
    if isinstance(identifier, str) and ":" in identifier:
        _, _, identifier = identifier.partition(":")

    dispatch = SignalDispatch(
        identifier=identifier,
        trace=document_data["trace"],
    )

    status = DispatchStatus(document_data.get("dispatchStatus", DispatchStatus.PENDING.value))
    if status == DispatchStatus.PUBLISHED:
        published_event = EventType(document_data["publishedEvent"])
        dispatch.publish(published_event, document_data["processedAt"])
    elif status == DispatchStatus.FAILED:
        reason_code = ReasonCode(document_data["reasonCode"])
        dispatch.fail(reason_code, document_data["processedAt"])

    return dispatch


def _document_identifier(identifier: str) -> str:
    """SignalDispatch の保存に使う idempotency_keys ドキュメントIDを返す。"""
    if identifier.startswith(f"{_SERVICE_NAME}:"):
        return identifier
    return f"{_SERVICE_NAME}:{identifier}"
