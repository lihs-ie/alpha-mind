"""Tests for FirestoreSignalGenerationRepository."""

import datetime
from unittest.mock import MagicMock

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
from signal_generator.infrastructure.firestore.firestore_signal_generation_repository import (
    FirestoreSignalGenerationRepository,
)


class TestFirestoreSignalGenerationRepository:
    """FirestoreSignalGenerationRepository のテスト。"""

    def test_implements_abstract_interface(self) -> None:
        mock_client = MagicMock()
        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        assert isinstance(repository, SignalGenerationRepository)

    def test_find_returns_pending_signal_generation(self) -> None:
        mock_client = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        mock_document_snapshot.to_dict.return_value = {
            "identifier": "01JTEST000000000000000000",
            "trace": "01JTRACE00000000000000000",
            "status": "pending",
            "featureSnapshot": {
                "targetDate": "2026-03-05",
                "featureVersion": "fv-20260305",
                "storagePath": "gs://bucket/features/2026-03-05.parquet",
            },
            "universeCount": 100,
            "modelSnapshot": None,
            "signalArtifact": None,
            "modelDiagnosticsSnapshot": None,
            "failureDetail": None,
            "processedAt": None,
        }
        mock_client.collection.return_value.document.return_value.get.return_value = (
            mock_document_snapshot
        )

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        result = repository.find("01JTEST000000000000000000")

        assert result is not None
        assert result.identifier == "01JTEST000000000000000000"
        assert result.status == GenerationStatus.PENDING
        assert result.feature_snapshot.target_date == datetime.date(2026, 3, 5)
        assert result.feature_snapshot.feature_version == "fv-20260305"
        assert result.universe_count == 100

    def test_find_returns_generated_signal_generation(self) -> None:
        mock_client = MagicMock()
        processed_at = datetime.datetime(2026, 3, 5, 10, 30, 0, tzinfo=datetime.UTC)
        approved_at = datetime.datetime(2026, 3, 1, 12, 0, 0, tzinfo=datetime.UTC)
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        mock_document_snapshot.to_dict.return_value = {
            "identifier": "01JTEST000000000000000000",
            "trace": "01JTRACE00000000000000000",
            "status": "generated",
            "featureSnapshot": {
                "targetDate": "2026-03-05",
                "featureVersion": "fv-20260305",
                "storagePath": "gs://bucket/features/2026-03-05.parquet",
            },
            "universeCount": 50,
            "modelSnapshot": {
                "modelVersion": "v1.0.0",
                "status": "approved",
                "approvedAt": approved_at,
            },
            "signalArtifact": {
                "signalVersion": "sv-20260305",
                "storagePath": "gs://bucket/signals/2026-03-05.parquet",
                "generatedCount": 50,
                "universeCount": 50,
            },
            "modelDiagnosticsSnapshot": {
                "degradationFlag": "normal",
                "requiresComplianceReview": False,
                "costAdjustedReturn": 0.05,
                "slippageAdjustedSharpe": 1.1,
            },
            "failureDetail": None,
            "processedAt": processed_at,
        }
        mock_client.collection.return_value.document.return_value.get.return_value = (
            mock_document_snapshot
        )

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        result = repository.find("01JTEST000000000000000000")

        assert result is not None
        assert result.status == GenerationStatus.GENERATED
        assert result.model_snapshot is not None
        assert result.model_snapshot.model_version == "v1.0.0"
        assert result.signal_artifact is not None
        assert result.signal_artifact.signal_version == "sv-20260305"
        assert result.model_diagnostics_snapshot is not None
        assert (
            result.model_diagnostics_snapshot.degradation_flag == DegradationFlag.NORMAL
        )

    def test_find_returns_failed_signal_generation(self) -> None:
        mock_client = MagicMock()
        processed_at = datetime.datetime(2026, 3, 5, 10, 30, 0, tzinfo=datetime.UTC)
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        mock_document_snapshot.to_dict.return_value = {
            "identifier": "01JTEST000000000000000000",
            "trace": "01JTRACE00000000000000000",
            "status": "failed",
            "featureSnapshot": {
                "targetDate": "2026-03-05",
                "featureVersion": "fv-20260305",
                "storagePath": "gs://bucket/features/2026-03-05.parquet",
            },
            "universeCount": 100,
            "modelSnapshot": None,
            "signalArtifact": None,
            "modelDiagnosticsSnapshot": None,
            "failureDetail": {
                "reasonCode": "MODEL_NOT_APPROVED",
                "retryable": False,
                "detail": "Model v0.9.0 is not approved",
            },
            "processedAt": processed_at,
        }
        mock_client.collection.return_value.document.return_value.get.return_value = (
            mock_document_snapshot
        )

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        result = repository.find("01JTEST000000000000000000")

        assert result is not None
        assert result.status == GenerationStatus.FAILED
        assert result.failure_detail is not None
        assert result.failure_detail.reason_code == ReasonCode.MODEL_NOT_APPROVED
        assert result.failure_detail.retryable is False

    def test_find_returns_none_when_not_found(self) -> None:
        mock_client = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = False
        mock_client.collection.return_value.document.return_value.get.return_value = (
            mock_document_snapshot
        )

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        result = repository.find("01JTEST_NONEXISTENT")

        assert result is None

    def test_persist_pending_signal_generation(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = (
            mock_document_reference
        )

        feature_snapshot = FeatureSnapshot(
            target_date=datetime.date(2026, 3, 5),
            feature_version="fv-20260305",
            storage_path="gs://bucket/features/2026-03-05.parquet",
        )
        signal_generation = SignalGeneration(
            identifier="01JTEST000000000000000000",
            feature_snapshot=feature_snapshot,
            universe_count=100,
            trace="01JTRACE00000000000000000",
        )

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        repository.persist(signal_generation)

        mock_client.collection.assert_called_once_with("signal_generations")
        call_args = mock_document_reference.set.call_args
        document_data = call_args[0][0]

        assert document_data["identifier"] == "01JTEST000000000000000000"
        assert document_data["status"] == "pending"
        assert document_data["featureSnapshot"]["targetDate"] == "2026-03-05"
        assert document_data["featureSnapshot"]["featureVersion"] == "fv-20260305"
        assert document_data["universeCount"] == 100

    def test_persist_generated_signal_generation(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = (
            mock_document_reference
        )

        feature_snapshot = FeatureSnapshot(
            target_date=datetime.date(2026, 3, 5),
            feature_version="fv-20260305",
            storage_path="gs://bucket/features/2026-03-05.parquet",
        )
        signal_generation = SignalGeneration(
            identifier="01JTEST000000000000000000",
            feature_snapshot=feature_snapshot,
            universe_count=50,
            trace="01JTRACE00000000000000000",
        )
        model_snapshot = ModelSnapshot(
            model_version="v1.0.0",
            status=ModelStatus.APPROVED,
            approved_at=datetime.datetime(2026, 3, 1, 12, 0, 0, tzinfo=datetime.UTC),
        )
        signal_generation.resolve_model(model_snapshot)
        signal_artifact = SignalArtifact(
            signal_version="sv-20260305",
            storage_path="gs://bucket/signals/2026-03-05.parquet",
            generated_count=50,
            universe_count=50,
        )
        model_diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        )
        processed_at = datetime.datetime(2026, 3, 5, 10, 30, 0, tzinfo=datetime.UTC)
        signal_generation.complete(signal_artifact, model_diagnostics, processed_at)

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        repository.persist(signal_generation)

        call_args = mock_document_reference.set.call_args
        document_data = call_args[0][0]

        assert document_data["status"] == "generated"
        assert document_data["modelSnapshot"]["modelVersion"] == "v1.0.0"
        assert document_data["signalArtifact"]["signalVersion"] == "sv-20260305"
        assert document_data["modelDiagnosticsSnapshot"]["degradationFlag"] == "normal"

    def test_persist_failed_signal_generation(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = (
            mock_document_reference
        )

        feature_snapshot = FeatureSnapshot(
            target_date=datetime.date(2026, 3, 5),
            feature_version="fv-20260305",
            storage_path="gs://bucket/features/2026-03-05.parquet",
        )
        signal_generation = SignalGeneration(
            identifier="01JTEST000000000000000000",
            feature_snapshot=feature_snapshot,
            universe_count=100,
            trace="01JTRACE00000000000000000",
        )
        failure_detail = FailureDetail(
            reason_code=ReasonCode.MODEL_NOT_APPROVED,
            retryable=False,
            detail="Model v0.9.0 is not approved",
        )
        processed_at = datetime.datetime(2026, 3, 5, 10, 30, 0, tzinfo=datetime.UTC)
        signal_generation.fail(failure_detail, processed_at)

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        repository.persist(signal_generation)

        call_args = mock_document_reference.set.call_args
        document_data = call_args[0][0]

        assert document_data["status"] == "failed"
        assert document_data["failureDetail"] is not None
        assert document_data["failureDetail"]["reasonCode"] == "MODEL_NOT_APPROVED"
        assert document_data["failureDetail"]["retryable"] is False
        assert document_data["failureDetail"]["detail"] == "Model v0.9.0 is not approved"

    def test_find_by_status_returns_matching_generations(self) -> None:
        mock_client = MagicMock()
        mock_document = MagicMock()
        mock_document.to_dict.return_value = {
            "identifier": "01JTEST000000000000000000",
            "trace": "01JTRACE00000000000000000",
            "status": "pending",
            "featureSnapshot": {
                "targetDate": "2026-03-05",
                "featureVersion": "fv-20260305",
                "storagePath": "gs://bucket/features/2026-03-05.parquet",
            },
            "universeCount": 100,
            "modelSnapshot": None,
            "signalArtifact": None,
            "modelDiagnosticsSnapshot": None,
            "failureDetail": None,
            "processedAt": None,
        }
        mock_client.collection.return_value.where.return_value.stream.return_value = (
            iter([mock_document])
        )

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        results = repository.find_by_status(GenerationStatus.PENDING)

        assert len(results) == 1
        assert results[0].identifier == "01JTEST000000000000000000"

    def test_search_returns_matching_generations(self) -> None:
        mock_client = MagicMock()
        mock_document = MagicMock()
        mock_document.to_dict.return_value = {
            "identifier": "01JTEST000000000000000000",
            "trace": "01JTRACE00000000000000000",
            "status": "pending",
            "featureSnapshot": {
                "targetDate": "2026-03-05",
                "featureVersion": "fv-20260305",
                "storagePath": "gs://bucket/features/2026-03-05.parquet",
            },
            "universeCount": 100,
            "modelSnapshot": None,
            "signalArtifact": None,
            "modelDiagnosticsSnapshot": None,
            "failureDetail": None,
            "processedAt": None,
        }
        mock_query = MagicMock()
        mock_query.stream.return_value = iter([mock_document])
        mock_client.collection.return_value.where.return_value = mock_query

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        results = repository.search({"status": "pending"})

        assert len(results) == 1

    def test_terminate_deletes_document(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = (
            mock_document_reference
        )

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        repository.terminate("01JTEST000000000000000000")

        mock_client.collection.assert_called_once_with("signal_generations")
        mock_document_reference.delete.assert_called_once()
