"""Tests for FirestoreSignalGenerationRepository."""

from __future__ import annotations

import datetime
from unittest.mock import MagicMock

from signal_generator.domain.aggregates.signal_generation import SignalGeneration
from signal_generator.domain.enums.generation_status import GenerationStatus
from signal_generator.domain.repositories.signal_generation_repository import (
    SignalGenerationRepository,
)
from signal_generator.domain.value_objects.feature_snapshot import FeatureSnapshot
from signal_generator.infrastructure.firestore.firestore_signal_generation_repository import (
    FirestoreSignalGenerationRepository,
)


def _create_feature_snapshot() -> FeatureSnapshot:
    return FeatureSnapshot(
        target_date=datetime.date(2026, 3, 5),
        feature_version="v1.0.0",
        storage_path="gs://features/2026-03-05/v1.0.0.parquet",
    )


class TestFirestoreSignalGenerationRepository:
    """FirestoreSignalGenerationRepository のテスト。"""

    def test_implements_abstract_interface(self) -> None:
        mock_client = MagicMock()
        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        assert isinstance(repository, SignalGenerationRepository)

    def test_find_returns_none_when_document_does_not_exist(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = False
        mock_document_reference.get.return_value = mock_document_snapshot
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        result = repository.find("01JTEST0000000000000000000")

        assert result is None
        mock_client.collection.assert_called_once_with("signal_runs")

    def test_persist_calls_set_with_document_data(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        generation = SignalGeneration(
            identifier="01JTEST0000000000000000000",
            feature_snapshot=_create_feature_snapshot(),
            universe_count=100,
            trace="01JTRACE000000000000000000",
        )
        repository.persist(generation)

        mock_client.collection.assert_called_once_with("signal_runs")
        mock_client.collection.return_value.document.assert_called_once_with("01JTEST0000000000000000000")
        mock_document_reference.set.assert_called_once()

        document_data = mock_document_reference.set.call_args[0][0]
        assert document_data["identifier"] == "01JTEST0000000000000000000"
        assert document_data["status"] == "pending"
        assert document_data["trace"] == "01JTRACE000000000000000000"
        assert document_data["universeCount"] == 100

    def test_terminate_deletes_document(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        repository.terminate("01JTEST0000000000000000000")

        mock_client.collection.assert_called_once_with("signal_runs")
        mock_document_reference.delete.assert_called_once()

    def test_find_by_status_queries_with_status_filter(self) -> None:
        mock_client = MagicMock()
        mock_query = MagicMock()
        mock_query.stream.return_value = []
        mock_client.collection.return_value.where.return_value = mock_query

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        result = repository.find_by_status(GenerationStatus.PENDING)

        assert result == []
        mock_client.collection.return_value.where.assert_called_once_with("status", "==", "pending")

    def test_find_returns_pending_generation(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        mock_document_snapshot.to_dict.return_value = {
            "identifier": "01JTEST0000000000000000000",
            "status": "pending",
            "featureSnapshot": {
                "targetDate": "2026-03-05",
                "featureVersion": "v1.0.0",
                "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
            },
            "universeCount": 100,
            "trace": "01JTRACE000000000000000000",
            "processedAt": None,
        }
        mock_document_reference.get.return_value = mock_document_snapshot
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        result = repository.find("01JTEST0000000000000000000")

        assert result is not None
        assert result.identifier == "01JTEST0000000000000000000"
        assert result.status == GenerationStatus.PENDING

    def test_find_returns_generated_generation(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        mock_document_snapshot.to_dict.return_value = {
            "identifier": "01JTEST0000000000000000000",
            "status": "generated",
            "featureSnapshot": {
                "targetDate": "2026-03-05",
                "featureVersion": "v1.0.0",
                "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
            },
            "universeCount": 100,
            "trace": "01JTRACE000000000000000000",
            "processedAt": processed_at,
            "modelSnapshot": {
                "modelVersion": "v1.0.0",
                "status": "approved",
                "approvedAt": processed_at.isoformat(),
            },
            "signalArtifact": {
                "signalVersion": "sv-20260305",
                "storagePath": "gs://signals/2026-03-05.parquet",
                "generatedCount": 100,
                "universeCount": 100,
            },
            "modelDiagnosticsSnapshot": {
                "degradationFlag": "normal",
                "requiresComplianceReview": False,
            },
        }
        mock_document_reference.get.return_value = mock_document_snapshot
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        result = repository.find("01JTEST0000000000000000000")

        assert result is not None
        assert result.status == GenerationStatus.GENERATED
        assert result.signal_artifact is not None
        assert result.signal_artifact.signal_version == "sv-20260305"

    def test_find_returns_failed_generation(self) -> None:
        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_document_snapshot = MagicMock()
        mock_document_snapshot.exists = True
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        mock_document_snapshot.to_dict.return_value = {
            "identifier": "01JTEST0000000000000000000",
            "status": "failed",
            "featureSnapshot": {
                "targetDate": "2026-03-05",
                "featureVersion": "v1.0.0",
                "storagePath": "gs://features/2026-03-05/v1.0.0.parquet",
            },
            "universeCount": 100,
            "trace": "01JTRACE000000000000000000",
            "processedAt": processed_at,
            "failureDetail": {
                "reasonCode": "MODEL_NOT_APPROVED",
                "retryable": False,
                "detail": "No approved model found",
            },
        }
        mock_document_reference.get.return_value = mock_document_snapshot
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        result = repository.find("01JTEST0000000000000000000")

        assert result is not None
        assert result.status == GenerationStatus.FAILED
        assert result.failure_detail is not None

    def test_search_queries_with_criteria(self) -> None:
        mock_client = MagicMock()
        mock_query = MagicMock()
        mock_query.where.return_value = mock_query
        mock_query.stream.return_value = []
        mock_client.collection.return_value = mock_query

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        result = repository.search({"trace": "01JTRACE000000000000000000"})

        assert result == []

    def test_persist_generated_includes_signal_artifact(self) -> None:
        from signal_generator.domain.enums.degradation_flag import DegradationFlag
        from signal_generator.domain.enums.model_status import ModelStatus
        from signal_generator.domain.value_objects.model_diagnostics_snapshot import (
            ModelDiagnosticsSnapshot,
        )
        from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot
        from signal_generator.domain.value_objects.signal_artifact import SignalArtifact

        mock_client = MagicMock()
        mock_document_reference = MagicMock()
        mock_client.collection.return_value.document.return_value = mock_document_reference

        repository = FirestoreSignalGenerationRepository(firestore_client=mock_client)
        generation = SignalGeneration(
            identifier="01JTEST0000000000000000000",
            feature_snapshot=_create_feature_snapshot(),
            universe_count=100,
            trace="01JTRACE000000000000000000",
        )
        processed_at = datetime.datetime(2026, 3, 5, 10, 0, 0, tzinfo=datetime.UTC)
        model_snapshot = ModelSnapshot(
            model_version="v1.0.0",
            status=ModelStatus.APPROVED,
            approved_at=processed_at,
        )
        generation.resolve_model(model_snapshot)
        signal_artifact = SignalArtifact(
            signal_version="sv-20260305",
            storage_path="gs://signals/2026-03-05.parquet",
            generated_count=100,
            universe_count=100,
        )
        model_diagnostics = ModelDiagnosticsSnapshot(
            degradation_flag=DegradationFlag.NORMAL,
            requires_compliance_review=False,
        )
        generation.complete(signal_artifact, model_diagnostics, processed_at)

        repository.persist(generation)

        document_data = mock_document_reference.set.call_args[0][0]
        assert document_data["status"] == "generated"
        assert "signalArtifact" in document_data
        assert "modelSnapshot" in document_data
        assert "modelDiagnosticsSnapshot" in document_data
        assert document_data["modelDiagnosticsSnapshot"]["degradationFlag"] == "normal"
        assert document_data["modelDiagnosticsSnapshot"]["requiresComplianceReview"] is False
