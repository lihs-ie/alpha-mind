"""Tests for FirestoreFeatureGenerationRepository."""

import datetime
from unittest.mock import MagicMock

import pytest

from domain.model.feature_generation import FeatureGeneration
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
from infrastructure.persistence.firestore.firestore_feature_generation_repository import (
    FirestoreFeatureGenerationRepository,
)

VALID_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
VALID_TRACE = "01ARZ3NDEKTSV4RRFFQ69G5FAW"


def _make_pending_generation() -> FeatureGeneration:
    return FeatureGeneration(
        identifier=VALID_ULID,
        status=FeatureGenerationStatus.PENDING,
        market=MarketSnapshot(
            target_date=datetime.date(2026, 1, 15),
            storage_path="gs://raw_market_data/2026-01-15/market.parquet",
            source_status=SourceStatus(
                jp=SourceStatusValue.OK,
                us=SourceStatusValue.OK,
            ),
        ),
        trace=VALID_TRACE,
    )


def _make_generated_generation() -> FeatureGeneration:
    return FeatureGeneration(
        identifier=VALID_ULID,
        status=FeatureGenerationStatus.GENERATED,
        market=MarketSnapshot(
            target_date=datetime.date(2026, 1, 15),
            storage_path="gs://raw_market_data/2026-01-15/market.parquet",
            source_status=SourceStatus(
                jp=SourceStatusValue.OK,
                us=SourceStatusValue.OK,
            ),
        ),
        trace=VALID_TRACE,
        insight=InsightSnapshot(
            record_count=42,
            latest_collected_at=datetime.datetime(2026, 1, 15, 8, 0, 0, tzinfo=datetime.UTC),
            filtered_by_target_date=True,
        ),
        feature_artifact=FeatureArtifact(
            feature_version="v20260115-001",
            storage_path="gs://feature_store/v20260115-001/features.parquet",
            row_count=100,
            feature_count=25,
        ),
        processed_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
    )


def _make_failed_generation() -> FeatureGeneration:
    return FeatureGeneration(
        identifier=VALID_ULID,
        status=FeatureGenerationStatus.FAILED,
        market=MarketSnapshot(
            target_date=datetime.date(2026, 1, 15),
            storage_path="gs://raw_market_data/2026-01-15/market.parquet",
            source_status=SourceStatus(
                jp=SourceStatusValue.OK,
                us=SourceStatusValue.FAILED,
            ),
        ),
        trace=VALID_TRACE,
        failure_detail=FailureDetail(
            reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
            detail="US market data source unavailable",
            retryable=True,
        ),
        processed_at=datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
    )


class TestFirestoreFeatureGenerationRepositoryPersist:
    """persist() should serialize FeatureGeneration to Firestore document."""

    def test_persist_pending_generation(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        generation = _make_pending_generation()

        repository.persist(generation)

        mock_client.collection.assert_called_once_with("feature_generations")
        mock_collection.document.assert_called_once_with(VALID_ULID)
        mock_document.set.assert_called_once()

        persisted_data = mock_document.set.call_args[0][0]
        assert persisted_data["identifier"] == VALID_ULID
        assert persisted_data["status"] == "pending"
        assert persisted_data["market"]["targetDate"] == "2026-01-15"
        assert persisted_data["market"]["storagePath"] == "gs://raw_market_data/2026-01-15/market.parquet"
        assert persisted_data["market"]["sourceStatus"]["jp"] == "ok"
        assert persisted_data["market"]["sourceStatus"]["us"] == "ok"
        assert persisted_data["trace"] == VALID_TRACE
        assert persisted_data["insight"] is None
        assert persisted_data["featureArtifact"] is None
        assert persisted_data["failureDetail"] is None
        assert persisted_data["processedAt"] is None
        assert persisted_data["updatedAt"] is None

    def test_persist_generated_generation(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        generation = _make_generated_generation()

        repository.persist(generation)

        persisted_data = mock_document.set.call_args[0][0]
        assert persisted_data["status"] == "generated"
        assert persisted_data["insight"]["recordCount"] == 42
        assert persisted_data["insight"]["latestCollectedAt"] == datetime.datetime(
            2026, 1, 15, 8, 0, 0, tzinfo=datetime.UTC
        )
        assert persisted_data["insight"]["filteredByTargetDate"] is True
        assert persisted_data["featureArtifact"]["featureVersion"] == "v20260115-001"
        assert persisted_data["featureArtifact"]["storagePath"] == "gs://feature_store/v20260115-001/features.parquet"
        assert persisted_data["featureArtifact"]["rowCount"] == 100
        assert persisted_data["featureArtifact"]["featureCount"] == 25
        assert persisted_data["processedAt"] == datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC)
        assert persisted_data["updatedAt"] == datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC)

    def test_persist_failed_generation(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        generation = _make_failed_generation()

        repository.persist(generation)

        persisted_data = mock_document.set.call_args[0][0]
        assert persisted_data["status"] == "failed"
        assert persisted_data["failureDetail"]["reasonCode"] == "DEPENDENCY_UNAVAILABLE"
        assert persisted_data["failureDetail"]["detail"] == "US market data source unavailable"
        assert persisted_data["failureDetail"]["retryable"] is True


class TestFirestoreFeatureGenerationRepositoryFind:
    """find() should deserialize Firestore document back to FeatureGeneration."""

    def test_find_returns_none_when_not_found(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = False

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        result = repository.find(VALID_ULID)

        assert result is None

    def test_find_returns_pending_generation(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = {
            "identifier": VALID_ULID,
            "status": "pending",
            "market": {
                "targetDate": "2026-01-15",
                "storagePath": "gs://raw_market_data/2026-01-15/market.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            },
            "trace": VALID_TRACE,
            "insight": None,
            "featureArtifact": None,
            "failureDetail": None,
            "processedAt": None,
        }

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        result = repository.find(VALID_ULID)

        assert result is not None
        assert result.identifier == VALID_ULID
        assert result.status == FeatureGenerationStatus.PENDING
        assert result.market.target_date == datetime.date(2026, 1, 15)
        assert result.market.source_status.jp == SourceStatusValue.OK
        assert result.market.source_status.us == SourceStatusValue.OK
        assert result.trace == VALID_TRACE
        assert result.insight is None
        assert result.feature_artifact is None

    def test_find_returns_generated_generation(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = {
            "identifier": VALID_ULID,
            "status": "generated",
            "market": {
                "targetDate": "2026-01-15",
                "storagePath": "gs://raw_market_data/2026-01-15/market.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            },
            "trace": VALID_TRACE,
            "insight": {
                "recordCount": 42,
                "latestCollectedAt": datetime.datetime(2026, 1, 15, 8, 0, 0, tzinfo=datetime.UTC),
                "filteredByTargetDate": True,
            },
            "featureArtifact": {
                "featureVersion": "v20260115-001",
                "storagePath": "gs://feature_store/v20260115-001/features.parquet",
                "rowCount": 100,
                "featureCount": 25,
            },
            "failureDetail": None,
            "processedAt": datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        }

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        result = repository.find(VALID_ULID)

        assert result is not None
        assert result.status == FeatureGenerationStatus.GENERATED
        assert result.insight is not None
        assert result.insight.record_count == 42
        assert result.feature_artifact is not None
        assert result.feature_artifact.feature_version == "v20260115-001"
        assert result.processed_at == datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC)

    def test_find_returns_failed_generation(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = {
            "identifier": VALID_ULID,
            "status": "failed",
            "market": {
                "targetDate": "2026-01-15",
                "storagePath": "gs://raw_market_data/2026-01-15/market.parquet",
                "sourceStatus": {"jp": "ok", "us": "failed"},
            },
            "trace": VALID_TRACE,
            "insight": None,
            "featureArtifact": None,
            "failureDetail": {
                "reasonCode": "DEPENDENCY_UNAVAILABLE",
                "detail": "US market data source unavailable",
                "retryable": True,
            },
            "processedAt": datetime.datetime(2026, 1, 15, 9, 0, 0, tzinfo=datetime.UTC),
        }

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        result = repository.find(VALID_ULID)

        assert result is not None
        assert result.status == FeatureGenerationStatus.FAILED
        assert result.failure_detail is not None
        assert result.failure_detail.reason_code == ReasonCode.DEPENDENCY_UNAVAILABLE
        assert result.failure_detail.retryable is True


class TestFirestoreFeatureGenerationRepositoryFindByStatus:
    """find_by_status() should query Firestore by status field."""

    def test_find_by_status_returns_matching_documents(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_query = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.where.return_value = mock_query

        mock_doc = MagicMock()
        mock_doc.to_dict.return_value = {
            "identifier": VALID_ULID,
            "status": "pending",
            "market": {
                "targetDate": "2026-01-15",
                "storagePath": "gs://raw_market_data/2026-01-15/market.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            },
            "trace": VALID_TRACE,
            "insight": None,
            "featureArtifact": None,
            "failureDetail": None,
            "processedAt": None,
        }
        mock_query.stream.return_value = [mock_doc]

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        results = repository.find_by_status(FeatureGenerationStatus.PENDING)

        assert len(results) == 1
        assert results[0].identifier == VALID_ULID
        assert results[0].status == FeatureGenerationStatus.PENDING
        mock_collection.where.assert_called_once_with(filter=mock_collection.where.call_args.kwargs["filter"])

    def test_find_by_status_returns_empty_list(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_query = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.where.return_value = mock_query
        mock_query.stream.return_value = []

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        results = repository.find_by_status(FeatureGenerationStatus.GENERATED)

        assert results == []


class TestFirestoreFeatureGenerationRepositorySearch:
    """search() should query Firestore with optional target_date filter."""

    def test_search_without_filter_returns_all(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_client.collection.return_value = mock_collection

        mock_doc = MagicMock()
        mock_doc.to_dict.return_value = {
            "identifier": VALID_ULID,
            "status": "pending",
            "market": {
                "targetDate": "2026-01-15",
                "storagePath": "gs://raw_market_data/2026-01-15/market.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            },
            "trace": VALID_TRACE,
            "insight": None,
            "featureArtifact": None,
            "failureDetail": None,
            "processedAt": None,
        }
        mock_collection.stream.return_value = [mock_doc]

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        results = repository.search()

        assert len(results) == 1
        mock_collection.stream.assert_called_once()

    def test_search_with_target_date_filters(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_query = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.where.return_value = mock_query

        mock_doc = MagicMock()
        mock_doc.to_dict.return_value = {
            "identifier": VALID_ULID,
            "status": "pending",
            "market": {
                "targetDate": "2026-01-15",
                "storagePath": "gs://raw_market_data/2026-01-15/market.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            },
            "trace": VALID_TRACE,
            "insight": None,
            "featureArtifact": None,
            "failureDetail": None,
            "processedAt": None,
        }
        mock_query.stream.return_value = [mock_doc]

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        results = repository.search(target_date=datetime.date(2026, 1, 15))

        assert len(results) == 1
        mock_collection.where.assert_called_once()


class TestFirestoreFeatureGenerationRepositoryTerminate:
    """terminate() should delete the document from Firestore."""

    def test_terminate_deletes_document(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        repository.terminate(VALID_ULID)

        mock_client.collection.assert_called_once_with("feature_generations")
        mock_collection.document.assert_called_once_with(VALID_ULID)
        mock_document.delete.assert_called_once()


class TestFirestoreFeatureGenerationRepositoryDeserializeErrors:
    """Deserialization should raise clear errors for malformed Firestore documents."""

    def test_find_raises_for_missing_market_field(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = {
            "identifier": VALID_ULID,
            "status": "pending",
            "trace": VALID_TRACE,
            # "market" field is missing
        }

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        with pytest.raises(InfrastructureDataFormatError):
            repository.find(VALID_ULID)

    def test_find_raises_for_invalid_status(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_document = MagicMock()
        mock_snapshot = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.document.return_value = mock_document
        mock_document.get.return_value = mock_snapshot
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = {
            "identifier": VALID_ULID,
            "status": "unknown_status",
            "market": {
                "targetDate": "2026-01-15",
                "storagePath": "gs://test/path",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            },
            "trace": VALID_TRACE,
        }

        repository = FirestoreFeatureGenerationRepository(client=mock_client)
        with pytest.raises(InfrastructureDataFormatError):
            repository.find(VALID_ULID)
