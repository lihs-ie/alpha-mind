"""Firestore implementation of FeatureGenerationRepository."""

from __future__ import annotations

import datetime
from typing import Any, cast

from google.cloud.firestore_v1 import Client, FieldFilter
from google.cloud.firestore_v1.base_document import DocumentSnapshot

from domain.model.feature_generation import FeatureGeneration
from domain.repository.feature_generation_repository import FeatureGenerationRepository
from domain.value_object.enums import (
    FeatureGenerationStatus,
    ReasonCode,
    SourceStatusValue,
)
from domain.value_object.failure_detail import FailureDetail
from domain.value_object.feature_artifact import FeatureArtifact
from domain.value_object.insight_snapshot import InsightSnapshot
from domain.value_object.market_snapshot import MarketSnapshot
from domain.value_object.source_status import SourceStatus
from infrastructure.error import InfrastructureDataFormatError

COLLECTION_NAME = "feature_generations"


class FirestoreFeatureGenerationRepository(FeatureGenerationRepository):
    """Firestore-backed repository for FeatureGeneration aggregates."""

    def __init__(self, client: Client) -> None:
        self._client = client

    def find(self, identifier: str) -> FeatureGeneration | None:
        snapshot = cast(DocumentSnapshot, self._client.collection(COLLECTION_NAME).document(identifier).get())
        if not snapshot.exists:
            return None
        data = snapshot.to_dict()
        if data is None:
            return None
        return _deserialize(data)

    def find_by_status(self, status: FeatureGenerationStatus) -> list[FeatureGeneration]:
        query = self._client.collection(COLLECTION_NAME).where(filter=FieldFilter("status", "==", status.value))
        return [_deserialize(data) for document in query.stream() if (data := document.to_dict()) is not None]

    def search(self, target_date: datetime.date | None = None) -> list[FeatureGeneration]:
        collection_reference = self._client.collection(COLLECTION_NAME)
        if target_date is not None:
            query = collection_reference.where(filter=FieldFilter("market.targetDate", "==", target_date.isoformat()))
            return [_deserialize(data) for document in query.stream() if (data := document.to_dict()) is not None]
        return [
            _deserialize(data) for document in collection_reference.stream() if (data := document.to_dict()) is not None
        ]

    def persist(self, feature_generation: FeatureGeneration) -> None:
        data = _serialize(feature_generation)
        self._client.collection(COLLECTION_NAME).document(feature_generation.identifier).set(data)

    def terminate(self, identifier: str) -> None:
        self._client.collection(COLLECTION_NAME).document(identifier).delete()


def _serialize(generation: FeatureGeneration) -> dict[str, Any]:
    """Convert FeatureGeneration aggregate to Firestore document."""
    insight_data: dict[str, Any] | None = None
    if generation.insight is not None:
        insight_data = {
            "recordCount": generation.insight.record_count,
            "latestCollectedAt": generation.insight.latest_collected_at,
            "filteredByTargetDate": generation.insight.filtered_by_target_date,
        }

    artifact_data: dict[str, Any] | None = None
    if generation.feature_artifact is not None:
        artifact_data = {
            "featureVersion": generation.feature_artifact.feature_version,
            "storagePath": generation.feature_artifact.storage_path,
            "rowCount": generation.feature_artifact.row_count,
            "featureCount": generation.feature_artifact.feature_count,
        }

    failure_data: dict[str, Any] | None = None
    if generation.failure_detail is not None:
        failure_data = {
            "reasonCode": generation.failure_detail.reason_code.value,
            "detail": generation.failure_detail.detail,
            "retryable": generation.failure_detail.retryable,
        }

    return {
        "identifier": generation.identifier,
        "status": generation.status.value,
        "market": {
            "targetDate": generation.market.target_date.isoformat(),
            "storagePath": generation.market.storage_path,
            "sourceStatus": {
                "jp": generation.market.source_status.jp.value,
                "us": generation.market.source_status.us.value,
            },
        },
        "trace": generation.trace,
        "insight": insight_data,
        "featureArtifact": artifact_data,
        "failureDetail": failure_data,
        "processedAt": generation.processed_at,
        "updatedAt": generation.processed_at,
    }


def _deserialize(data: dict[str, Any]) -> FeatureGeneration:
    """Reconstruct FeatureGeneration aggregate from Firestore document."""
    try:
        market_data = data["market"]
        source_status_data = market_data["sourceStatus"]

        market = MarketSnapshot(
            target_date=datetime.date.fromisoformat(market_data["targetDate"]),
            storage_path=market_data["storagePath"],
            source_status=SourceStatus(
                jp=SourceStatusValue(source_status_data["jp"]),
                us=SourceStatusValue(source_status_data["us"]),
            ),
        )

        insight: InsightSnapshot | None = None
        if data.get("insight") is not None:
            insight_data = data["insight"]
            insight = InsightSnapshot(
                record_count=insight_data["recordCount"],
                latest_collected_at=insight_data["latestCollectedAt"],
                filtered_by_target_date=insight_data["filteredByTargetDate"],
            )

        feature_artifact: FeatureArtifact | None = None
        if data.get("featureArtifact") is not None:
            artifact_data = data["featureArtifact"]
            feature_artifact = FeatureArtifact(
                feature_version=artifact_data["featureVersion"],
                storage_path=artifact_data["storagePath"],
                row_count=artifact_data["rowCount"],
                feature_count=artifact_data["featureCount"],
            )

        failure_detail: FailureDetail | None = None
        if data.get("failureDetail") is not None:
            failure_data = data["failureDetail"]
            failure_detail = FailureDetail(
                reason_code=ReasonCode(failure_data["reasonCode"]),
                detail=failure_data["detail"],
                retryable=failure_data["retryable"],
            )

        return FeatureGeneration(
            identifier=data["identifier"],
            status=FeatureGenerationStatus(data["status"]),
            market=market,
            trace=data["trace"],
            insight=insight,
            feature_artifact=feature_artifact,
            failure_detail=failure_detail,
            processed_at=data.get("processedAt"),
        )
    except (KeyError, ValueError) as error:
        raise InfrastructureDataFormatError(
            source=COLLECTION_NAME,
            detail=f"Failed to deserialize document: {error}",
            cause=error,
        ) from error
