"""Firestore implementation of SignalGenerationRepository."""

import datetime
from typing import Any

from google.cloud.firestore_v1 import Client as FirestoreClient
from google.cloud.firestore_v1.base_document import DocumentSnapshot
from google.cloud.firestore_v1.base_query import BaseQuery

from signal_generator.domain.aggregates.signal_generation import SignalGeneration
from signal_generator.domain.enums.degradation_flag import DegradationFlag
from signal_generator.domain.enums.generation_status import GenerationStatus
from signal_generator.domain.enums.model_status import ModelStatus
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.repositories.signal_generation_repository import (
    SignalGenerationRepository,
)
from signal_generator.domain.value_objects.failure_detail import FailureDetail
from signal_generator.domain.value_objects.feature_snapshot import FeatureSnapshot
from signal_generator.domain.value_objects.model_diagnostics_snapshot import (
    ModelDiagnosticsSnapshot,
)
from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot
from signal_generator.domain.value_objects.signal_artifact import SignalArtifact

_COLLECTION_NAME = "signal_generations"


class FirestoreSignalGenerationRepository(SignalGenerationRepository):
    """SignalGeneration 集約の Firestore 永続化実装。"""

    def __init__(self, firestore_client: FirestoreClient) -> None:
        self._firestore_client = firestore_client

    def find(self, identifier: str) -> SignalGeneration | None:
        document_reference = self._firestore_client.collection(_COLLECTION_NAME).document(identifier)
        document_snapshot: DocumentSnapshot = document_reference.get()  # type: ignore[assignment]
        if not document_snapshot.exists:
            return None
        return _to_signal_generation(document_snapshot.to_dict())

    def find_by_status(self, status: GenerationStatus) -> list[SignalGeneration]:
        documents = self._firestore_client.collection(_COLLECTION_NAME).where("status", "==", status.value).stream()
        return [_to_signal_generation(document.to_dict()) for document in documents]

    def search(self, criteria: dict[str, object]) -> list[SignalGeneration]:
        query: BaseQuery = self._firestore_client.collection(_COLLECTION_NAME)  # type: ignore[assignment]
        for field_name, value in criteria.items():
            query = query.where(field_name, "==", value)
        return [
            _to_signal_generation(document.to_dict())
            for document in query.stream()  # type: ignore[union-attr]
        ]

    def persist(self, signal_generation: SignalGeneration) -> None:
        document_data = _from_signal_generation(signal_generation)
        document_reference = self._firestore_client.collection(_COLLECTION_NAME).document(signal_generation.identifier)
        document_reference.set(document_data)

    def terminate(self, identifier: str) -> None:
        document_reference = self._firestore_client.collection(_COLLECTION_NAME).document(identifier)
        document_reference.delete()


def _to_signal_generation(document_data: dict[str, Any] | None) -> SignalGeneration:
    """Firestore ドキュメントから SignalGeneration 集約を復元する。"""
    if document_data is None:
        raise ValueError("document_data must not be None")

    feature_snapshot_data = document_data["featureSnapshot"]
    feature_snapshot = FeatureSnapshot(
        target_date=datetime.date.fromisoformat(feature_snapshot_data["targetDate"]),
        feature_version=feature_snapshot_data["featureVersion"],
        storage_path=feature_snapshot_data["storagePath"],
    )

    signal_generation = SignalGeneration(
        identifier=document_data["identifier"],
        feature_snapshot=feature_snapshot,
        universe_count=document_data["universeCount"],
        trace=document_data["trace"],
    )

    status = GenerationStatus(document_data["status"])
    processed_at: datetime.datetime | None = document_data.get("processedAt")

    if status == GenerationStatus.GENERATED:
        model_snapshot_data = document_data["modelSnapshot"]
        model_snapshot = ModelSnapshot(
            model_version=model_snapshot_data["modelVersion"],
            status=ModelStatus(model_snapshot_data["status"]),
            approved_at=model_snapshot_data.get("approvedAt"),
        )
        signal_generation.resolve_model(model_snapshot)

        signal_artifact_data = document_data["signalArtifact"]
        signal_artifact = SignalArtifact(
            signal_version=signal_artifact_data["signalVersion"],
            storage_path=signal_artifact_data["storagePath"],
            generated_count=signal_artifact_data["generatedCount"],
            universe_count=signal_artifact_data["universeCount"],
        )

        diagnostics_data = document_data["modelDiagnosticsSnapshot"]
        model_diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag(diagnostics_data["degradationFlag"]),
            requires_compliance_review=diagnostics_data["requiresComplianceReview"],
            cost_adjusted_return=diagnostics_data.get("costAdjustedReturn"),
            slippage_adjusted_sharpe=diagnostics_data.get("slippageAdjustedSharpe"),
        )

        assert processed_at is not None
        signal_generation.complete(signal_artifact, model_diagnostics, processed_at)

    elif status == GenerationStatus.FAILED:
        model_snapshot_data = document_data.get("modelSnapshot")
        if model_snapshot_data is not None:
            model_snapshot = ModelSnapshot(
                model_version=model_snapshot_data["modelVersion"],
                status=ModelStatus(model_snapshot_data["status"]),
                approved_at=model_snapshot_data.get("approvedAt"),
            )
            signal_generation.resolve_model(model_snapshot)

        failure_detail_data = document_data["failureDetail"]
        failure_detail = FailureDetail(
            reason_code=ReasonCode(failure_detail_data["reasonCode"]),
            retryable=failure_detail_data["retryable"],
            detail=failure_detail_data.get("detail"),
        )
        assert processed_at is not None
        signal_generation.fail(failure_detail, processed_at)

    return signal_generation


def _from_signal_generation(signal_generation: SignalGeneration) -> dict[str, Any]:
    """SignalGeneration 集約を Firestore ドキュメントに変換する。"""
    feature_snapshot = signal_generation.feature_snapshot

    document_data: dict[str, Any] = {
        "identifier": signal_generation.identifier,
        "trace": signal_generation.trace,
        "status": signal_generation.status.value,
        "featureSnapshot": {
            "targetDate": feature_snapshot.target_date.isoformat(),
            "featureVersion": feature_snapshot.feature_version,
            "storagePath": feature_snapshot.storage_path,
        },
        "universeCount": signal_generation.universe_count,
        "modelSnapshot": None,
        "signalArtifact": None,
        "modelDiagnosticsSnapshot": None,
        "failureDetail": None,
        "processedAt": signal_generation.processed_at,
    }

    if signal_generation.model_snapshot is not None:
        model_snapshot = signal_generation.model_snapshot
        document_data["modelSnapshot"] = {
            "modelVersion": model_snapshot.model_version,
            "status": model_snapshot.status.value,
            "approvedAt": model_snapshot.approved_at,
        }

    if signal_generation.signal_artifact is not None:
        signal_artifact = signal_generation.signal_artifact
        document_data["signalArtifact"] = {
            "signalVersion": signal_artifact.signal_version,
            "storagePath": signal_artifact.storage_path,
            "generatedCount": signal_artifact.generated_count,
            "universeCount": signal_artifact.universe_count,
        }

    if signal_generation.model_diagnostics_snapshot is not None:
        diagnostics = signal_generation.model_diagnostics_snapshot
        document_data["modelDiagnosticsSnapshot"] = {
            "degradationFlag": diagnostics.degradation_flag.value,
            "requiresComplianceReview": diagnostics.requires_compliance_review,
            "costAdjustedReturn": diagnostics.cost_adjusted_return,
            "slippageAdjustedSharpe": diagnostics.slippage_adjusted_sharpe,
        }

    if signal_generation.failure_detail is not None:
        failure_detail = signal_generation.failure_detail
        document_data["failureDetail"] = {
            "reasonCode": failure_detail.reason_code.value,
            "retryable": failure_detail.retryable,
            "detail": failure_detail.detail,
        }

    return document_data
