"""Tests for HypothesisWorkflowService application service."""

from __future__ import annotations

import datetime
from collections.abc import Callable
from typing import Any
from unittest.mock import MagicMock

import pytest

from application.hypothesis_workflow_service import (
    EventEnvelope,
    HypothesisWorkflowService,
    RetryableHypothesisError,
    StateConflictHypothesisError,
)
from domain.event.domain_events import HypothesisBacktested, HypothesisPromoted, HypothesisRejected
from domain.factory.hypothesis_factory import HypothesisFactory
from domain.model.hypothesis import Hypothesis
from domain.repository.failure_knowledge_repository import FailureKnowledgeRepository
from domain.repository.hypothesis_repository import HypothesisRepository
from domain.repository.idempotency_key_repository import IdempotencyKeyRepository, ReservationStatus
from domain.repository.validation_run_repository import ValidationRunRepository
from domain.service.promotion_eligibility_policy import PromotionEligibilityPolicy
from domain.specification.promotion_ready_specification import PromotionReadySpecification
from domain.value_object.enums import HypothesisStatus, InsiderRisk, InstrumentType

_NOW = datetime.datetime(2026, 3, 1, 12, 0, 0, tzinfo=datetime.UTC)
_TRACE = "01JNPQRS000000000000000001"
_ENVELOPE_IDENTIFIER = "01JNPQRS000000000000000099"
_HYPOTHESIS_IDENTIFIER = "01JNPQRS000000000000000010"


def _fixed_clock(timestamp: datetime.datetime) -> Callable[[], datetime.datetime]:
    """Return a clock callable that always returns the given timestamp."""
    return lambda: timestamp


def _make_proposed_envelope(
    *,
    identifier: str = _ENVELOPE_IDENTIFIER,
    cost_adjusted_return: float = 0.15,
    dsr: float = 0.5,
    pbo: float = 0.3,
    instrument_type: str = "ETF",
    symbol: str = "1234",
) -> EventEnvelope:
    return EventEnvelope(
        identifier=identifier,
        event_type="hypothesis.proposed",
        occurred_at=_NOW,
        trace=_TRACE,
        payload={
            "title": "Test ETF hypothesis",
            "sourceEvidence": ["insight-001", "insight-002"],
            "skillVersion": "v1.0.0",
            "instructionProfileVersion": "v1.0.0",
            "symbol": symbol,
            "instrumentType": instrument_type,
            "insiderRisk": "low",
            "requiresComplianceReview": False,
            "backtestMetrics": {
                "costAdjustedReturn": cost_adjusted_return,
                "dsr": dsr,
                "pbo": pbo,
            },
        },
    )


def _make_demo_completed_envelope(
    *,
    identifier: str = _ENVELOPE_IDENTIFIER,
    hypothesis_identifier: str = _HYPOTHESIS_IDENTIFIER,
    promotable: bool = True,
    demo_period_days: int = 30,
) -> EventEnvelope:
    started_at = datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC)
    ended_at = started_at + datetime.timedelta(days=demo_period_days)
    return EventEnvelope(
        identifier=identifier,
        event_type="hypothesis.demo.completed",
        occurred_at=_NOW,
        trace=_TRACE,
        payload={
            "hypothesisIdentifier": hypothesis_identifier,
            "promotable": promotable,
            "startedAt": started_at.isoformat(),
            "endedAt": ended_at.isoformat(),
            "demoPeriodDays": demo_period_days,
        },
    )


def _make_demo_etf_hypothesis(identifier: str = _HYPOTHESIS_IDENTIFIER) -> Hypothesis:
    """Return a Hypothesis in DEMO status with all auto-promotion conditions met."""
    return Hypothesis(
        identifier=identifier,
        symbol="1234",
        instrument_type=InstrumentType.ETF,
        status=HypothesisStatus.DEMO,
        title="Test ETF hypothesis",
        source_evidence=["insight-001"],
        skill_version="v1.0.0",
        instruction_profile_version="v1.0.0",
        updated_at=_NOW,
        insider_risk=InsiderRisk.LOW,
        requires_compliance_review=False,
        mnpi_self_declared=True,
    )


def _make_demo_stock_hypothesis(identifier: str = _HYPOTHESIS_IDENTIFIER) -> Hypothesis:
    """Return a Hypothesis in DEMO status with STOCK instrument type."""
    return Hypothesis(
        identifier=identifier,
        symbol="7203",
        instrument_type=InstrumentType.STOCK,
        status=HypothesisStatus.DEMO,
        title="Test STOCK hypothesis",
        source_evidence=["insight-001"],
        skill_version="v1.0.0",
        instruction_profile_version="v1.0.0",
        updated_at=_NOW,
        insider_risk=InsiderRisk.LOW,
        requires_compliance_review=False,
        mnpi_self_declared=True,
    )


class FakeIdempotencyKeyRepository(IdempotencyKeyRepository):
    """In-memory idempotency key store for tests."""

    def __init__(self) -> None:
        self._processed: dict[str, datetime.datetime] = {}
        self._leased: set[str] = set()

    def find(self, identifier: str) -> datetime.datetime | None:
        return self._processed.get(identifier)

    def reserve(
        self,
        identifier: str,
        leased_at: datetime.datetime,
        lease_expires_at: datetime.datetime,
        trace: str,
    ) -> ReservationStatus:
        if identifier in self._processed:
            return ReservationStatus.PROCESSED
        if identifier in self._leased:
            return ReservationStatus.LEASED
        self._leased.add(identifier)
        return ReservationStatus.ACQUIRED

    def persist(self, identifier: str, processed_at: datetime.datetime, trace: str) -> None:
        self._leased.discard(identifier)
        self._processed[identifier] = processed_at

    def release(self, identifier: str, released_at: datetime.datetime) -> None:
        self._leased.discard(identifier)

    def terminate(self, identifier: str) -> None:
        self._processed.pop(identifier, None)
        self._leased.discard(identifier)

    def mark_leased(self, identifier: str) -> None:
        """Test helper: mark identifier as already leased."""
        self._leased.add(identifier)

    def mark_processed(self, identifier: str, processed_at: datetime.datetime) -> None:
        """Test helper: mark identifier as already processed."""
        self._processed[identifier] = processed_at


def _make_service(
    *,
    hypothesis_repository: HypothesisRepository | None = None,
    validation_run_repository: ValidationRunRepository | None = None,
    failure_knowledge_repository: FailureKnowledgeRepository | None = None,
    idempotency_key_repository: IdempotencyKeyRepository | None = None,
    hypothesis_backtested_publisher: Any = None,
    hypothesis_promoted_publisher: Any = None,
    hypothesis_rejected_publisher: Any = None,
) -> tuple[HypothesisWorkflowService, FakeIdempotencyKeyRepository]:
    fake_idempotency = idempotency_key_repository or FakeIdempotencyKeyRepository()
    service = HypothesisWorkflowService(
        hypothesis_repository=hypothesis_repository or MagicMock(spec=HypothesisRepository),
        validation_run_repository=validation_run_repository or MagicMock(spec=ValidationRunRepository),
        failure_knowledge_repository=failure_knowledge_repository or MagicMock(spec=FailureKnowledgeRepository),
        idempotency_key_repository=fake_idempotency,
        hypothesis_backtested_publisher=hypothesis_backtested_publisher or MagicMock(),
        hypothesis_promoted_publisher=hypothesis_promoted_publisher or MagicMock(),
        hypothesis_rejected_publisher=hypothesis_rejected_publisher or MagicMock(),
        hypothesis_factory=HypothesisFactory(),
        promotion_eligibility_policy=PromotionEligibilityPolicy(),
        promotion_ready_specification=PromotionReadySpecification(),
        partner_restricted_symbols=[],
        clock=_fixed_clock(_NOW),
    )
    return service, fake_idempotency  # type: ignore[return-value]


class TestProcessProposed:
    """Tests for HypothesisWorkflowService.process_proposed."""

    def test_creates_hypothesis_and_emits_backtested(self) -> None:
        """Passing backtest metrics lead to HypothesisBacktested being published."""
        hypothesis_repository = MagicMock(spec=HypothesisRepository)
        validation_run_repository = MagicMock(spec=ValidationRunRepository)
        backtested_publisher = MagicMock()

        service, _ = _make_service(
            hypothesis_repository=hypothesis_repository,
            validation_run_repository=validation_run_repository,
            hypothesis_backtested_publisher=backtested_publisher,
        )

        envelope = _make_proposed_envelope(cost_adjusted_return=0.15, dsr=0.5, pbo=0.3)
        service.process_proposed(envelope)

        hypothesis_repository.persist.assert_called_once()
        validation_run_repository.persist.assert_called_once()
        backtested_publisher.publish.assert_called_once()

        event: HypothesisBacktested = backtested_publisher.publish.call_args[0][0]
        assert isinstance(event, HypothesisBacktested)
        assert event.passed is True
        assert event.cost_adjusted_return == pytest.approx(0.15)
        assert event.dsr == pytest.approx(0.5)
        assert event.pbo == pytest.approx(0.3)

    def test_failing_backtest_emits_rejected(self) -> None:
        """Failing backtest metrics lead to HypothesisRejected being published."""
        hypothesis_repository = MagicMock(spec=HypothesisRepository)
        rejected_publisher = MagicMock()
        failure_knowledge_repository = MagicMock(spec=FailureKnowledgeRepository)

        service, _ = _make_service(
            hypothesis_repository=hypothesis_repository,
            failure_knowledge_repository=failure_knowledge_repository,
            hypothesis_rejected_publisher=rejected_publisher,
        )

        # pbo=0.8 > 0.5 fails the backtest
        envelope = _make_proposed_envelope(cost_adjusted_return=0.15, dsr=0.5, pbo=0.8)
        service.process_proposed(envelope)

        hypothesis_repository.persist.assert_called_once()
        rejected_publisher.publish.assert_called_once()
        failure_knowledge_repository.persist.assert_called_once()

        event: HypothesisRejected = rejected_publisher.publish.call_args[0][0]
        assert isinstance(event, HypothesisRejected)

    def test_idempotent_on_duplicate(self) -> None:
        """Duplicate event envelope is silently ignored."""
        hypothesis_repository = MagicMock(spec=HypothesisRepository)
        backtested_publisher = MagicMock()
        fake_idempotency = FakeIdempotencyKeyRepository()
        fake_idempotency.mark_processed(_ENVELOPE_IDENTIFIER, _NOW)

        service, _ = _make_service(
            hypothesis_repository=hypothesis_repository,
            idempotency_key_repository=fake_idempotency,
            hypothesis_backtested_publisher=backtested_publisher,
        )

        envelope = _make_proposed_envelope()
        service.process_proposed(envelope)

        # Neither persist nor publish should be called for a duplicate event
        hypothesis_repository.persist.assert_not_called()
        backtested_publisher.publish.assert_not_called()

    def test_raises_retryable_error_when_event_is_leased(self) -> None:
        """A concurrently leased event raises RetryableHypothesisError."""
        fake_idempotency = FakeIdempotencyKeyRepository()
        fake_idempotency.mark_leased(_ENVELOPE_IDENTIFIER)

        service, _ = _make_service(idempotency_key_repository=fake_idempotency)

        envelope = _make_proposed_envelope()
        with pytest.raises(RetryableHypothesisError) as exc_info:
            service.process_proposed(envelope)

        assert exc_info.value.retryable is True
        assert exc_info.value.status == 503

    def test_backtest_metrics_default_to_failing_when_absent(self) -> None:
        """Missing backtestMetrics default to zero values which fail the backtest."""
        hypothesis_repository = MagicMock(spec=HypothesisRepository)
        rejected_publisher = MagicMock()
        backtested_publisher = MagicMock()

        service, _ = _make_service(
            hypothesis_repository=hypothesis_repository,
            hypothesis_rejected_publisher=rejected_publisher,
            hypothesis_backtested_publisher=backtested_publisher,
        )

        envelope = EventEnvelope(
            identifier=_ENVELOPE_IDENTIFIER,
            event_type="hypothesis.proposed",
            occurred_at=_NOW,
            trace=_TRACE,
            payload={
                "title": "Test ETF hypothesis",
                "sourceEvidence": ["insight-001"],
                "skillVersion": "v1.0.0",
                "instructionProfileVersion": "v1.0.0",
                "symbol": "1234",
                "instrumentType": "ETF",
                # no backtestMetrics
            },
        )
        service.process_proposed(envelope)

        # Zero metrics fail the backtest → rejected
        rejected_publisher.publish.assert_called_once()
        backtested_publisher.publish.assert_called_once()

    def test_marks_idempotency_key_after_processing(self) -> None:
        """After successful processing, the idempotency key is marked as processed."""
        fake_idempotency = FakeIdempotencyKeyRepository()

        service, _ = _make_service(idempotency_key_repository=fake_idempotency)

        envelope = _make_proposed_envelope()
        service.process_proposed(envelope)

        assert fake_idempotency.find(_ENVELOPE_IDENTIFIER) is not None


class TestProcessDemoCompleted:
    """Tests for HypothesisWorkflowService.process_demo_completed."""

    def test_auto_promotes_etf_hypothesis(self) -> None:
        """ETF hypothesis with all conditions met is auto-promoted and HypothesisPromoted published."""
        hypothesis_repository = MagicMock(spec=HypothesisRepository)
        hypothesis_repository.find.return_value = _make_demo_etf_hypothesis()
        promoted_publisher = MagicMock()
        validation_run_repository = MagicMock(spec=ValidationRunRepository)

        service, _ = _make_service(
            hypothesis_repository=hypothesis_repository,
            validation_run_repository=validation_run_repository,
            hypothesis_promoted_publisher=promoted_publisher,
        )

        envelope = _make_demo_completed_envelope(
            hypothesis_identifier=_HYPOTHESIS_IDENTIFIER,
            promotable=True,
            demo_period_days=30,
        )
        service.process_demo_completed(envelope)

        promoted_publisher.publish.assert_called_once()
        event: HypothesisPromoted = promoted_publisher.publish.call_args[0][0]
        assert isinstance(event, HypothesisPromoted)
        validation_run_repository.persist.assert_called_once()

    def test_does_not_auto_promote_stock(self) -> None:
        """STOCK hypothesis is never auto-promoted even with all other conditions met."""
        hypothesis_repository = MagicMock(spec=HypothesisRepository)
        hypothesis_repository.find.return_value = _make_demo_stock_hypothesis()
        promoted_publisher = MagicMock()

        service, _ = _make_service(
            hypothesis_repository=hypothesis_repository,
            hypothesis_promoted_publisher=promoted_publisher,
        )

        envelope = _make_demo_completed_envelope(
            hypothesis_identifier=_HYPOTHESIS_IDENTIFIER,
            promotable=True,
            demo_period_days=30,
        )
        service.process_demo_completed(envelope)

        # No promotion event for STOCK
        promoted_publisher.publish.assert_not_called()

    def test_rejects_when_promotable_false(self) -> None:
        """When promotable=false, hypothesis is rejected and HypothesisRejected published."""
        hypothesis_repository = MagicMock(spec=HypothesisRepository)
        hypothesis_repository.find.return_value = _make_demo_etf_hypothesis()
        rejected_publisher = MagicMock()
        failure_knowledge_repository = MagicMock(spec=FailureKnowledgeRepository)

        service, _ = _make_service(
            hypothesis_repository=hypothesis_repository,
            failure_knowledge_repository=failure_knowledge_repository,
            hypothesis_rejected_publisher=rejected_publisher,
        )

        envelope = _make_demo_completed_envelope(
            hypothesis_identifier=_HYPOTHESIS_IDENTIFIER,
            promotable=False,
            demo_period_days=30,
        )
        service.process_demo_completed(envelope)

        rejected_publisher.publish.assert_called_once()
        event: HypothesisRejected = rejected_publisher.publish.call_args[0][0]
        assert isinstance(event, HypothesisRejected)
        failure_knowledge_repository.persist.assert_called_once()

    def test_idempotent_on_duplicate_demo_event(self) -> None:
        """Duplicate demo.completed event envelope is silently ignored."""
        hypothesis_repository = MagicMock(spec=HypothesisRepository)
        promoted_publisher = MagicMock()
        fake_idempotency = FakeIdempotencyKeyRepository()
        fake_idempotency.mark_processed(_ENVELOPE_IDENTIFIER, _NOW)

        service, _ = _make_service(
            hypothesis_repository=hypothesis_repository,
            idempotency_key_repository=fake_idempotency,
            hypothesis_promoted_publisher=promoted_publisher,
        )

        envelope = _make_demo_completed_envelope(hypothesis_identifier=_HYPOTHESIS_IDENTIFIER)
        service.process_demo_completed(envelope)

        hypothesis_repository.find.assert_not_called()
        promoted_publisher.publish.assert_not_called()

    def test_raises_retryable_error_when_hypothesis_not_found(self) -> None:
        """Missing hypothesis raises RetryableHypothesisError."""
        hypothesis_repository = MagicMock(spec=HypothesisRepository)
        hypothesis_repository.find.return_value = None

        service, _ = _make_service(hypothesis_repository=hypothesis_repository)

        envelope = _make_demo_completed_envelope(hypothesis_identifier=_HYPOTHESIS_IDENTIFIER)
        with pytest.raises(RetryableHypothesisError) as exc_info:
            service.process_demo_completed(envelope)

        assert exc_info.value.status == 404
        assert exc_info.value.retryable is True

    def test_raises_error_when_hypothesis_identifier_missing(self) -> None:
        """Missing hypothesisIdentifier in payload raises RetryableHypothesisError."""
        service, _ = _make_service()

        envelope = EventEnvelope(
            identifier=_ENVELOPE_IDENTIFIER,
            event_type="hypothesis.demo.completed",
            occurred_at=_NOW,
            trace=_TRACE,
            payload={
                "promotable": True,
                "startedAt": "2026-01-01T00:00:00+00:00",
                "endedAt": "2026-02-01T00:00:00+00:00",
                "demoPeriodDays": 31,
            },
        )
        with pytest.raises(RetryableHypothesisError) as exc_info:
            service.process_demo_completed(envelope)

        assert exc_info.value.status == 400

    def test_persists_hypothesis_after_demo_completion(self) -> None:
        """Hypothesis is persisted after demo completion regardless of promotion outcome."""
        hypothesis_repository = MagicMock(spec=HypothesisRepository)
        hypothesis_repository.find.return_value = _make_demo_etf_hypothesis()

        service, _ = _make_service(hypothesis_repository=hypothesis_repository)

        envelope = _make_demo_completed_envelope(
            hypothesis_identifier=_HYPOTHESIS_IDENTIFIER,
            promotable=True,
            demo_period_days=30,
        )
        service.process_demo_completed(envelope)

        hypothesis_repository.persist.assert_called_once()

    def test_state_conflict_raises_when_hypothesis_not_in_demo(self) -> None:
        """Hypothesis not in DEMO status raises StateConflictHypothesisError."""
        backtested_hypothesis = Hypothesis(
            identifier=_HYPOTHESIS_IDENTIFIER,
            symbol="1234",
            instrument_type=InstrumentType.ETF,
            status=HypothesisStatus.BACKTESTED,
            title="Test ETF hypothesis",
            source_evidence=["insight-001"],
            skill_version="v1.0.0",
            instruction_profile_version="v1.0.0",
            updated_at=_NOW,
        )
        hypothesis_repository = MagicMock(spec=HypothesisRepository)
        hypothesis_repository.find.return_value = backtested_hypothesis

        service, _ = _make_service(hypothesis_repository=hypothesis_repository)

        envelope = _make_demo_completed_envelope(hypothesis_identifier=_HYPOTHESIS_IDENTIFIER)
        with pytest.raises(StateConflictHypothesisError) as exc_info:
            service.process_demo_completed(envelope)

        assert exc_info.value.retryable is False
