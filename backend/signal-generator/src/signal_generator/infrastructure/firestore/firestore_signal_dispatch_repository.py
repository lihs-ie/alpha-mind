"""Firestore implementation of SignalDispatchRepository."""


from google.cloud.firestore_v1 import Client as FirestoreClient

from signal_generator.domain.aggregates.signal_dispatch import SignalDispatch
from signal_generator.domain.enums.dispatch_status import DispatchStatus
from signal_generator.domain.enums.event_type import EventType
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.repositories.signal_dispatch_repository import (
    SignalDispatchRepository,
)

_COLLECTION_NAME = "signal_dispatches"


class FirestoreSignalDispatchRepository(SignalDispatchRepository):
    """SignalDispatch 集約の Firestore 永続化実装。"""

    def __init__(self, firestore_client: FirestoreClient) -> None:
        self._firestore_client = firestore_client

    def find(self, identifier: str) -> SignalDispatch | None:
        document_reference = self._firestore_client.collection(
            _COLLECTION_NAME
        ).document(identifier)
        document_snapshot = document_reference.get()
        if not document_snapshot.exists:
            return None
        return _to_signal_dispatch(document_snapshot.to_dict())

    def persist(self, signal_dispatch: SignalDispatch) -> None:
        document_data = _from_signal_dispatch(signal_dispatch)
        document_reference = self._firestore_client.collection(
            _COLLECTION_NAME
        ).document(signal_dispatch.identifier)
        document_reference.set(document_data)

    def terminate(self, identifier: str) -> None:
        document_reference = self._firestore_client.collection(
            _COLLECTION_NAME
        ).document(identifier)
        document_reference.delete()


def _to_signal_dispatch(document_data: dict) -> SignalDispatch:
    """Firestore ドキュメントから SignalDispatch 集約を復元する。"""
    signal_dispatch = SignalDispatch(
        identifier=document_data["identifier"],
        trace=document_data["trace"],
    )

    dispatch_status = DispatchStatus(document_data["dispatchStatus"])
    processed_at = document_data.get("processedAt")

    if dispatch_status == DispatchStatus.PUBLISHED:
        published_event = EventType(document_data["publishedEvent"])
        signal_dispatch.publish(published_event, processed_at)
    elif dispatch_status == DispatchStatus.FAILED:
        reason_code = ReasonCode(document_data["reasonCode"])
        signal_dispatch.fail(reason_code, processed_at)

    return signal_dispatch


def _from_signal_dispatch(signal_dispatch: SignalDispatch) -> dict:
    """SignalDispatch 集約を Firestore ドキュメントに変換する。"""
    return {
        "identifier": signal_dispatch.identifier,
        "trace": signal_dispatch.trace,
        "dispatchStatus": signal_dispatch.dispatch_status.value,
        "publishedEvent": (
            signal_dispatch.published_event.value
            if signal_dispatch.published_event is not None
            else None
        ),
        "reasonCode": (
            signal_dispatch.reason_code.value
            if signal_dispatch.reason_code is not None
            else None
        ),
        "processedAt": signal_dispatch.processed_at,
    }
