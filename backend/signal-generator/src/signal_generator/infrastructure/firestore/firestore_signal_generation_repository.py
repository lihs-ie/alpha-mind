"""Firestore implementation of SignalGenerationRepository."""

from typing import Any, cast

from google.cloud.firestore_v1 import Client as FirestoreClient
from google.cloud.firestore_v1.base_document import DocumentSnapshot
from google.cloud.firestore_v1.query import Query

from signal_generator.domain.aggregates.signal_generation import SignalGeneration
from signal_generator.domain.enums.generation_status import GenerationStatus
from signal_generator.domain.repositories.signal_generation_repository import (
    SignalGenerationRepository,
)

_COLLECTION_NAME = "signal_runs"


class FirestoreSignalGenerationRepository(SignalGenerationRepository):
    """signal_generations コレクションを使った SignalGeneration 永続化リポジトリ。"""

    def __init__(self, firestore_client: FirestoreClient) -> None:
        self._firestore_client = firestore_client

    def find(self, identifier: str) -> SignalGeneration | None:
        document_reference = self._firestore_client.collection(_COLLECTION_NAME).document(identifier)
        document_snapshot = cast(DocumentSnapshot, document_reference.get())
        if not document_snapshot.exists:
            return None
        return _to_signal_generation(document_snapshot.to_dict())

    def find_by_status(self, status: GenerationStatus) -> list[SignalGeneration]:
        query = self._firestore_client.collection(_COLLECTION_NAME).where("status", "==", status.value)
        return [_to_signal_generation(document.to_dict()) for document in query.stream()]

    def search(self, criteria: dict[str, object]) -> list[SignalGeneration]:
        collection = self._firestore_client.collection(_COLLECTION_NAME)
        if not criteria:
            return [_to_signal_generation(document.to_dict()) for document in collection.stream()]
        items = list(criteria.items())
        query: Query = collection.where(items[0][0], "==", items[0][1])
        for field_name, value in items[1:]:
            query = query.where(field_name, "==", value)
        return [_to_signal_generation(document.to_dict()) for document in query.stream()]

    def persist(self, signal_generation: SignalGeneration) -> None:
        document_data = _to_document_data(signal_generation)
        document_reference = self._firestore_client.collection(_COLLECTION_NAME).document(signal_generation.identifier)
        document_reference.set(document_data)

    def terminate(self, identifier: str) -> None:
        document_reference = self._firestore_client.collection(_COLLECTION_NAME).document(identifier)
        document_reference.delete()


def _to_document_data(signal_generation: SignalGeneration) -> dict[str, Any]:
    """SignalGeneration 集約を Firestore ドキュメントデータに変換する。"""
    document_data: dict[str, Any] = {
        "identifier": signal_generation.identifier,
        "status": signal_generation.status.value,
        "featureSnapshot": {
            "targetDate": signal_generation.feature_snapshot.target_date.isoformat(),
            "featureVersion": signal_generation.feature_snapshot.feature_version,
            "storagePath": signal_generation.feature_snapshot.storage_path,
        },
        "universeCount": signal_generation.universe_count,
        "trace": signal_generation.trace,
        "processedAt": signal_generation.processed_at,
    }
    if signal_generation.model_snapshot is not None:
        model_snapshot_data: dict[str, Any] = {
            "modelVersion": signal_generation.model_snapshot.model_version,
            "status": signal_generation.model_snapshot.status.value,
        }
        if signal_generation.model_snapshot.approved_at is not None:
            model_snapshot_data["approvedAt"] = signal_generation.model_snapshot.approved_at.isoformat()
        document_data["modelSnapshot"] = model_snapshot_data
    if signal_generation.signal_artifact is not None:
        document_data["signalArtifact"] = {
            "signalVersion": signal_generation.signal_artifact.signal_version,
            "storagePath": signal_generation.signal_artifact.storage_path,
            "generatedCount": signal_generation.signal_artifact.generated_count,
            "universeCount": signal_generation.signal_artifact.universe_count,
        }
    if signal_generation.model_diagnostics_snapshot is not None:
        diagnostics = signal_generation.model_diagnostics_snapshot
        diagnostics_data: dict[str, Any] = {
            "degradationFlag": diagnostics.degradation_flag.value,
            "requiresComplianceReview": diagnostics.requires_compliance_review,
        }
        if diagnostics.cost_adjusted_return is not None:
            diagnostics_data["costAdjustedReturn"] = diagnostics.cost_adjusted_return
        if diagnostics.slippage_adjusted_sharpe is not None:
            diagnostics_data["slippageAdjustedSharpe"] = diagnostics.slippage_adjusted_sharpe
        document_data["modelDiagnosticsSnapshot"] = diagnostics_data
    if signal_generation.failure_detail is not None:
        document_data["failureDetail"] = {
            "reasonCode": signal_generation.failure_detail.reason_code.value,
            "retryable": signal_generation.failure_detail.retryable,
            "detail": signal_generation.failure_detail.detail,
        }
    return document_data


def _to_signal_generation(document_data: dict[str, Any] | None) -> SignalGeneration:
    """Firestore ドキュメントを SignalGeneration 集約に変換する。

    注意: Firestore からの復元時は集約のライフサイクルメソッド (complete/fail) を
    呼び出さず、内部状態を直接復元する。これは永続化の都合であり、
    ドメインの不変条件は persist 時に保証されている。
    """
    if document_data is None:
        raise ValueError("document_data must not be None")

    from datetime import date, datetime

    from signal_generator.domain.value_objects.feature_snapshot import FeatureSnapshot

    feature_data = document_data["featureSnapshot"]
    feature_snapshot = FeatureSnapshot(
        target_date=date.fromisoformat(feature_data["targetDate"]),
        feature_version=feature_data["featureVersion"],
        storage_path=feature_data["storagePath"],
    )

    generation = SignalGeneration(
        identifier=document_data["identifier"],
        feature_snapshot=feature_snapshot,
        universe_count=document_data["universeCount"],
        trace=document_data["trace"],
    )

    status = GenerationStatus(document_data["status"])
    if status == GenerationStatus.GENERATED:
        from signal_generator.domain.enums.degradation_flag import DegradationFlag
        from signal_generator.domain.enums.model_status import ModelStatus
        from signal_generator.domain.value_objects.model_diagnostics_snapshot import (
            ModelDiagnosticsSnapshot,
        )
        from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot
        from signal_generator.domain.value_objects.signal_artifact import SignalArtifact

        model_data = document_data.get("modelSnapshot", {})
        approved_at_raw = model_data.get("approvedAt")
        approved_at = datetime.fromisoformat(approved_at_raw) if isinstance(approved_at_raw, str) else approved_at_raw
        model_snapshot = ModelSnapshot(
            model_version=model_data["modelVersion"],
            status=ModelStatus(model_data["status"]),
            approved_at=approved_at,
        )
        generation.resolve_model(model_snapshot)

        artifact_data = document_data["signalArtifact"]
        signal_artifact = SignalArtifact(
            signal_version=artifact_data["signalVersion"],
            storage_path=artifact_data["storagePath"],
            generated_count=artifact_data["generatedCount"],
            universe_count=artifact_data["universeCount"],
        )
        diagnostics_data = document_data.get("modelDiagnosticsSnapshot", {})
        model_diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag(diagnostics_data.get("degradationFlag", "normal")),
            requires_compliance_review=diagnostics_data.get("requiresComplianceReview", False),
        )
        generation.complete(signal_artifact, model_diagnostics, document_data["processedAt"])

    elif status == GenerationStatus.FAILED:
        from signal_generator.domain.enums.reason_code import ReasonCode
        from signal_generator.domain.value_objects.failure_detail import FailureDetail

        failure_data = document_data["failureDetail"]
        failure_detail = FailureDetail(
            reason_code=ReasonCode(failure_data["reasonCode"]),
            retryable=failure_data["retryable"],
            detail=failure_data.get("detail"),
        )
        generation.fail(failure_detail, document_data["processedAt"])

    return generation
