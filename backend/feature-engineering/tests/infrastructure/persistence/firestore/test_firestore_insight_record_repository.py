"""Tests for FirestoreInsightRecordRepository."""

import datetime
from unittest.mock import MagicMock, patch

from domain.value_object.insight_snapshot import InsightSnapshot
from infrastructure.persistence.firestore.firestore_insight_record_repository import (
    FirestoreInsightRecordRepository,
)


class TestFirestoreInsightRecordRepositorySearch:
    def test_search_without_filter_returns_all_snapshots(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_client.collection.return_value = mock_collection

        mock_doc1 = MagicMock()
        mock_doc1.to_dict.return_value = {
            "collectedAt": datetime.datetime(2026, 1, 15, 8, 0, 0, tzinfo=datetime.UTC),
        }
        mock_doc2 = MagicMock()
        mock_doc2.to_dict.return_value = {
            "collectedAt": datetime.datetime(2026, 1, 14, 7, 0, 0, tzinfo=datetime.UTC),
        }
        mock_collection.stream.return_value = [mock_doc1, mock_doc2]

        repository = FirestoreInsightRecordRepository(client=mock_client)
        results = repository.search()

        assert len(results) == 1
        snapshot = results[0]
        assert isinstance(snapshot, InsightSnapshot)
        assert snapshot.record_count == 2
        assert snapshot.filtered_by_target_date is False

    def test_search_with_target_date_includes_historical_records(self) -> None:
        """Per RULE-FE-003, collectedAt <= targetDate records are included."""
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_query = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.where.return_value = mock_query

        # Records from before and on the target date should all be included
        mock_doc1 = MagicMock()
        mock_doc1.to_dict.return_value = {
            "collectedAt": datetime.datetime(2026, 1, 13, 8, 0, 0, tzinfo=datetime.UTC),
        }
        mock_doc2 = MagicMock()
        mock_doc2.to_dict.return_value = {
            "collectedAt": datetime.datetime(2026, 1, 15, 8, 0, 0, tzinfo=datetime.UTC),
        }
        mock_query.stream.return_value = [mock_doc1, mock_doc2]

        repository = FirestoreInsightRecordRepository(client=mock_client)
        results = repository.search(target_date=datetime.date(2026, 1, 15))

        assert len(results) == 1
        snapshot = results[0]
        assert snapshot.record_count == 2
        assert snapshot.filtered_by_target_date is True
        assert snapshot.latest_collected_at == datetime.datetime(2026, 1, 15, 8, 0, 0, tzinfo=datetime.UTC)

        # Verify only one where clause is used (collectedAt < end_of_target_date)
        mock_collection.where.assert_called_once()

    def test_search_with_target_date_boundary_uses_strict_less_than(self) -> None:
        """Verify the query filter uses < (not <=) with start of next day."""
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_query = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.where.return_value = mock_query
        mock_query.stream.return_value = []

        with patch(
            "infrastructure.persistence.firestore.firestore_insight_record_repository.FieldFilter"
        ) as mock_field_filter_class:
            mock_field_filter_class.return_value = MagicMock()
            mock_collection.where.return_value = mock_query

            repository = FirestoreInsightRecordRepository(client=mock_client)
            repository.search(target_date=datetime.date(2026, 1, 15))

            # Verify FieldFilter constructor was called with "<" and start of next day
            mock_field_filter_class.assert_called_once_with(
                "collectedAt",
                "<",
                datetime.datetime(2026, 1, 16, 0, 0, 0, tzinfo=datetime.UTC),
            )

    def test_search_returns_empty_when_no_records(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.stream.return_value = []

        repository = FirestoreInsightRecordRepository(client=mock_client)
        results = repository.search()

        assert len(results) == 1
        assert results[0].record_count == 0
        assert results[0].latest_collected_at is None


class TestFirestoreInsightRecordRepositoryFindByTargetDate:
    def test_find_by_target_date_returns_snapshot(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_query = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.where.return_value = mock_query

        mock_doc = MagicMock()
        mock_doc.to_dict.return_value = {
            "collectedAt": datetime.datetime(2026, 1, 15, 6, 0, 0, tzinfo=datetime.UTC),
        }
        mock_query.stream.return_value = [mock_doc]

        repository = FirestoreInsightRecordRepository(client=mock_client)
        result = repository.find_by_target_date(datetime.date(2026, 1, 15))

        assert result is not None
        assert result.record_count == 1
        assert result.filtered_by_target_date is True
        assert result.latest_collected_at == datetime.datetime(2026, 1, 15, 6, 0, 0, tzinfo=datetime.UTC)

    def test_find_by_target_date_returns_none_when_no_records(self) -> None:
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_query = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.where.return_value = mock_query
        mock_query.stream.return_value = []

        repository = FirestoreInsightRecordRepository(client=mock_client)
        result = repository.find_by_target_date(datetime.date(2026, 1, 15))

        assert result is None

    def test_find_by_target_date_includes_historical_records(self) -> None:
        """Per RULE-FE-003, records from before target date are also included."""
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_query = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.where.return_value = mock_query

        mock_doc1 = MagicMock()
        mock_doc1.to_dict.return_value = {
            "collectedAt": datetime.datetime(2026, 1, 13, 6, 0, 0, tzinfo=datetime.UTC),
        }
        mock_doc2 = MagicMock()
        mock_doc2.to_dict.return_value = {
            "collectedAt": datetime.datetime(2026, 1, 15, 10, 0, 0, tzinfo=datetime.UTC),
        }
        mock_query.stream.return_value = [mock_doc1, mock_doc2]

        repository = FirestoreInsightRecordRepository(client=mock_client)
        result = repository.find_by_target_date(datetime.date(2026, 1, 15))

        assert result is not None
        assert result.record_count == 2
        assert result.latest_collected_at == datetime.datetime(2026, 1, 15, 10, 0, 0, tzinfo=datetime.UTC)

    def test_find_by_target_date_excludes_next_day_midnight(self) -> None:
        """Records at exactly targetDate+1 day 00:00:00 UTC must be excluded."""
        mock_client = MagicMock()
        mock_collection = MagicMock()
        mock_query = MagicMock()
        mock_client.collection.return_value = mock_collection
        mock_collection.where.return_value = mock_query
        # Firestore query with < filter means server-side filtering,
        # so an empty result simulates the server excluding the record
        mock_query.stream.return_value = []

        repository = FirestoreInsightRecordRepository(client=mock_client)
        result = repository.find_by_target_date(datetime.date(2026, 1, 15))

        assert result is None
        # Verify the filter uses strict less-than with start of next day
        mock_collection.where.assert_called_once()
