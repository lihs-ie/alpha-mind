"""Application service for hypothesis workflow orchestration."""

from __future__ import annotations

import datetime
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Protocol

import ulid

from domain.event.domain_events import HypothesisBacktested, HypothesisPromoted, HypothesisRejected
from domain.factory.hypothesis_factory import HypothesisFactory
from domain.model.validation_run import ValidationRun
from domain.repository.failure_knowledge_repository import FailureKnowledgeRepository
from domain.repository.hypothesis_repository import HypothesisRepository
from domain.repository.idempotency_key_repository import IdempotencyKeyRepository, ReservationStatus
from domain.repository.validation_run_repository import ValidationRunRepository
from domain.service.promotion_eligibility_policy import PromotionEligibilityPolicy
from domain.specification.promotion_ready_specification import PromotionReadySpecification
from domain.value_object.demo_window import DemoWindow
from domain.value_object.enums import HypothesisStatus, ReasonCode, RunType
from domain.value_object.failure_summary import FailureSummary
from domain.value_object.performance_metrics import PerformanceMetrics


class HypothesisBacktestedPublisher(Protocol):
    """Publishes a HypothesisBacktested domain event."""

    def publish(self, event: HypothesisBacktested) -> str | None:
        """Publish the backtested event."""


class HypothesisPromotedPublisher(Protocol):
    """Publishes a HypothesisPromoted domain event."""

    def publish(self, event: HypothesisPromoted) -> str | None:
        """Publish the promoted event."""


class HypothesisRejectedPublisher(Protocol):
    """Publishes a HypothesisRejected domain event."""

    def publish(self, event: HypothesisRejected) -> str | None:
        """Publish the rejected event."""


class HypothesisProcessingError(Exception):
    """Base exception for hypothesis processing failures."""

    def __init__(
        self,
        *,
        status: int,
        title: str,
        detail: str,
        reason_code: ReasonCode,
        trace: str,
        retryable: bool,
    ) -> None:
        super().__init__(detail)
        self.status = status
        self.title = title
        self.detail = detail
        self.reason_code = reason_code
        self.trace = trace
        self.retryable = retryable


class RetryableHypothesisError(HypothesisProcessingError):
    """Raised when the request should be retried by Pub/Sub."""


class StateConflictHypothesisError(HypothesisProcessingError):
    """Raised when persisted state is internally inconsistent."""


@dataclass(frozen=True)
class EventEnvelope:
    """Normalized incoming event envelope for hypothesis-lab."""

    identifier: str
    event_type: str
    occurred_at: datetime.datetime
    trace: str
    payload: Mapping[str, object]


class HypothesisWorkflowService:
    """Orchestrates hypothesis lifecycle from incoming events to published domain events.

    Handles:
    - hypothesis.proposed -> backtest evaluation -> HypothesisBacktested (or HypothesisRejected)
    - hypothesis.demo.completed -> demo evaluation -> HypothesisPromoted or stays in demo or HypothesisRejected
    """

    _LEASE_SECONDS = 300

    def __init__(
        self,
        *,
        hypothesis_repository: HypothesisRepository,
        validation_run_repository: ValidationRunRepository,
        failure_knowledge_repository: FailureKnowledgeRepository,
        idempotency_key_repository: IdempotencyKeyRepository,
        hypothesis_backtested_publisher: HypothesisBacktestedPublisher,
        hypothesis_promoted_publisher: HypothesisPromotedPublisher,
        hypothesis_rejected_publisher: HypothesisRejectedPublisher,
        hypothesis_factory: HypothesisFactory,
        promotion_eligibility_policy: PromotionEligibilityPolicy,
        promotion_ready_specification: PromotionReadySpecification,
        partner_restricted_symbols: list[str],
        clock: Callable[[], datetime.datetime],
    ) -> None:
        self._hypothesis_repository = hypothesis_repository
        self._validation_run_repository = validation_run_repository
        self._failure_knowledge_repository = failure_knowledge_repository
        self._idempotency_key_repository = idempotency_key_repository
        self._hypothesis_backtested_publisher = hypothesis_backtested_publisher
        self._hypothesis_promoted_publisher = hypothesis_promoted_publisher
        self._hypothesis_rejected_publisher = hypothesis_rejected_publisher
        self._hypothesis_factory = hypothesis_factory
        self._promotion_eligibility_policy = promotion_eligibility_policy
        self._promotion_ready_specification = promotion_ready_specification
        self._partner_restricted_symbols = list(partner_restricted_symbols)
        self._clock = clock

    def process_proposed(self, envelope: EventEnvelope) -> None:
        """Process a hypothesis.proposed event.

        1. Check idempotency.
        2. Create Hypothesis via HypothesisFactory.
        3. Extract backtest metrics from payload.
        4. Apply backtest result, persist, publish events.
        5. Mark idempotency as processed.
        """
        leased_at = self._clock()
        lease_expires_at = leased_at + datetime.timedelta(seconds=self._LEASE_SECONDS)
        reservation = self._idempotency_key_repository.reserve(
            envelope.identifier,
            leased_at,
            lease_expires_at,
            envelope.trace,
        )
        if reservation == ReservationStatus.PROCESSED:
            return
        if reservation == ReservationStatus.LEASED:
            raise RetryableHypothesisError(
                status=503,
                title="Service Unavailable",
                detail="Event is already being processed by another worker.",
                reason_code=ReasonCode.STATE_CONFLICT,
                trace=envelope.trace,
                retryable=True,
            )

        try:
            self._process_proposed_reserved(envelope)
        except HypothesisProcessingError:
            self._idempotency_key_repository.release(envelope.identifier, self._clock())
            raise
        except Exception as error:
            self._idempotency_key_repository.release(envelope.identifier, self._clock())
            raise RetryableHypothesisError(
                status=500,
                title="Internal Server Error",
                detail="Hypothesis proposed processing failed unexpectedly.",
                reason_code=ReasonCode.STATE_CONFLICT,
                trace=envelope.trace,
                retryable=True,
            ) from error

    def _process_proposed_reserved(self, envelope: EventEnvelope) -> None:
        """Process a hypothesis.proposed event after idempotency reservation."""
        payload = envelope.payload

        # Generate a ULID for the new Hypothesis and ValidationRun
        hypothesis_identifier = str(ulid.ULID())
        validation_run_identifier = str(ulid.ULID())

        try:
            hypothesis = self._hypothesis_factory.from_proposed_event(
                event_payload=dict(payload),
                identifier=hypothesis_identifier,
                trace=envelope.trace,
                occurred_at=envelope.occurred_at,
            )
        except ValueError as error:
            raise RetryableHypothesisError(
                status=400,
                title="Bad Request",
                detail=str(error),
                reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
                trace=envelope.trace,
                retryable=False,
            ) from error

        metrics = self._extract_backtest_metrics(payload)
        backtest_passed = self._evaluate_backtest(metrics)
        now = self._clock()

        conflict_code = hypothesis.apply_backtest_result(
            passed=backtest_passed,
            performance_metrics=metrics,
            validation_run_identifier=validation_run_identifier,
            trace=envelope.trace,
            occurred_at=now,
        )
        if conflict_code is not None:
            raise StateConflictHypothesisError(
                status=409,
                title="Conflict",
                detail=f"Unexpected state after backtest: {conflict_code.value}",
                reason_code=conflict_code,
                trace=envelope.trace,
                retryable=False,
            )

        validation_run = ValidationRun(
            identifier=validation_run_identifier,
            hypothesis=hypothesis.identifier,
            run_type=RunType.BACKTEST,
            executed_at=now,
            metrics=metrics,
        )
        self._hypothesis_repository.persist(hypothesis)
        self._validation_run_repository.persist(validation_run)

        for domain_event in hypothesis.domain_events:
            if isinstance(domain_event, HypothesisBacktested):
                self._hypothesis_backtested_publisher.publish(domain_event)
            elif isinstance(domain_event, HypothesisRejected):
                self._hypothesis_rejected_publisher.publish(domain_event)
                self._record_backtest_failure(
                    hypothesis_identifier=hypothesis.identifier,
                    symbol=hypothesis.symbol,
                    metrics=metrics,
                    trace=envelope.trace,
                )
        hypothesis.clear_domain_events()

        self._idempotency_key_repository.persist(envelope.identifier, self._clock(), envelope.trace)

    def _extract_backtest_metrics(self, payload: Mapping[str, object]) -> PerformanceMetrics:
        """Extract Walk-forward/DSR/PBO metrics from event payload.

        Falls back to zero values when payload metrics are absent,
        which will fail the backtest evaluation.
        """
        backtest_metrics = payload.get("backtestMetrics")
        source: Mapping[str, object] = backtest_metrics if isinstance(backtest_metrics, dict) else payload
        cost_adjusted_return = self._extract_float(source, "costAdjustedReturn", default=0.0)
        dsr = self._extract_float(source, "dsr", default=0.0)
        pbo = self._extract_float(source, "pbo", default=1.0)
        return PerformanceMetrics(
            cost_adjusted_return=cost_adjusted_return,
            dsr=dsr,
            pbo=pbo,
        )

    @staticmethod
    def _extract_float(source: Mapping[str, object], key: str, default: float) -> float:
        """Extract a float value from a mapping with a fallback default."""
        value = source.get(key)
        if value is None:
            return default
        if isinstance(value, (int, float)):
            return float(value)
        try:
            return float(str(value))
        except ValueError, TypeError:
            return default

    def _evaluate_backtest(self, metrics: PerformanceMetrics) -> bool:
        """Evaluate Walk-forward/DSR/PBO pass criteria.

        Pass conditions (§5.2 hypothesis-lab design):
        - cost_adjusted_return > 0
        - dsr > 0
        - pbo < 0.5   (Probability of Backtest Overfitting below 50%)
        """
        return metrics.cost_adjusted_return > 0 and metrics.dsr > 0 and metrics.pbo < 0.5

    def _record_backtest_failure(
        self,
        hypothesis_identifier: str,
        symbol: str,
        metrics: PerformanceMetrics,
        trace: str,
    ) -> None:
        """Record a backtest failure in the failure knowledge base."""
        markdown_summary = (
            f"## Backtest Failure\n\n"
            f"- **Hypothesis**: `{hypothesis_identifier}`\n"
            f"- **Symbol**: `{symbol}`\n"
            f"- **Trace**: `{trace}`\n\n"
            f"### Metrics\n\n"
            f"| Metric | Value |\n"
            f"|--------|-------|\n"
            f"| Cost-Adjusted Return | {metrics.cost_adjusted_return:.4f} |\n"
            f"| DSR | {metrics.dsr:.4f} |\n"
            f"| PBO | {metrics.pbo:.4f} |\n\n"
            f"Backtest did not pass Walk-forward/DSR/PBO validation thresholds."
        )
        failure_summary = FailureSummary(
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            markdown_summary=markdown_summary,
        )
        self._failure_knowledge_repository.persist(failure_summary)

    def process_demo_completed(self, envelope: EventEnvelope) -> None:
        """Process a hypothesis.demo.completed event.

        1. Check idempotency.
        2. Find Hypothesis by identifier.
        3. Apply demo result.
        4. Publish HypothesisPromoted or HypothesisRejected based on outcome.
        5. Mark idempotency as processed.
        """
        leased_at = self._clock()
        lease_expires_at = leased_at + datetime.timedelta(seconds=self._LEASE_SECONDS)
        reservation = self._idempotency_key_repository.reserve(
            envelope.identifier,
            leased_at,
            lease_expires_at,
            envelope.trace,
        )
        if reservation == ReservationStatus.PROCESSED:
            return
        if reservation == ReservationStatus.LEASED:
            raise RetryableHypothesisError(
                status=503,
                title="Service Unavailable",
                detail="Event is already being processed by another worker.",
                reason_code=ReasonCode.STATE_CONFLICT,
                trace=envelope.trace,
                retryable=True,
            )

        try:
            self._process_demo_completed_reserved(envelope)
        except HypothesisProcessingError:
            self._idempotency_key_repository.release(envelope.identifier, self._clock())
            raise
        except Exception as error:
            self._idempotency_key_repository.release(envelope.identifier, self._clock())
            raise RetryableHypothesisError(
                status=500,
                title="Internal Server Error",
                detail="Demo completed processing failed unexpectedly.",
                reason_code=ReasonCode.STATE_CONFLICT,
                trace=envelope.trace,
                retryable=True,
            ) from error

    def _process_demo_completed_reserved(self, envelope: EventEnvelope) -> None:
        """Process a hypothesis.demo.completed event after idempotency reservation."""
        payload = envelope.payload

        hypothesis_identifier_raw = payload.get("hypothesisIdentifier") or payload.get("hypothesis")
        if not isinstance(hypothesis_identifier_raw, str) or not hypothesis_identifier_raw:
            raise RetryableHypothesisError(
                status=400,
                title="Bad Request",
                detail="payload.hypothesisIdentifier is missing or empty.",
                reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
                trace=envelope.trace,
                retryable=False,
            )
        hypothesis_identifier = hypothesis_identifier_raw

        hypothesis = self._hypothesis_repository.find(hypothesis_identifier)
        if hypothesis is None:
            raise RetryableHypothesisError(
                status=404,
                title="Not Found",
                detail=f"Hypothesis '{hypothesis_identifier}' not found.",
                reason_code=ReasonCode.STATE_CONFLICT,
                trace=envelope.trace,
                retryable=True,
            )

        demo_window = self._extract_demo_window(payload, envelope)
        promotable = bool(payload.get("promotable", False))
        now = self._clock()

        validation_run_identifier = str(ulid.ULID())

        conflict_code = hypothesis.apply_demo_result(
            demo_window=demo_window,
            promotable=promotable,
            validation_run_identifier=validation_run_identifier,
            partner_restricted_symbols=self._partner_restricted_symbols,
            trace=envelope.trace,
            occurred_at=now,
        )
        if conflict_code == ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT:
            self._idempotency_key_repository.persist(envelope.identifier, self._clock(), envelope.trace)
            return
        if conflict_code is not None:
            raise StateConflictHypothesisError(
                status=409,
                title="Conflict",
                detail=f"Cannot apply demo result: {conflict_code.value}",
                reason_code=conflict_code,
                trace=envelope.trace,
                retryable=False,
            )

        validation_run = ValidationRun(
            identifier=validation_run_identifier,
            hypothesis=hypothesis.identifier,
            run_type=RunType.DEMO,
            executed_at=now,
            demo_window=demo_window,
            promotable=promotable,
        )
        self._hypothesis_repository.persist(hypothesis)
        self._validation_run_repository.persist(validation_run)

        for domain_event in hypothesis.domain_events:
            if isinstance(domain_event, HypothesisPromoted):
                self._hypothesis_promoted_publisher.publish(domain_event)
            elif isinstance(domain_event, HypothesisRejected):
                self._hypothesis_rejected_publisher.publish(domain_event)
                self._record_demo_failure(
                    hypothesis_identifier=hypothesis.identifier,
                    symbol=hypothesis.symbol,
                    demo_window=demo_window,
                    trace=envelope.trace,
                )
        hypothesis.clear_domain_events()

        self._idempotency_key_repository.persist(envelope.identifier, self._clock(), envelope.trace)

    def _extract_demo_window(self, payload: Mapping[str, object], envelope: EventEnvelope) -> DemoWindow:
        """Extract DemoWindow from event payload."""
        started_at_raw = payload.get("startedAt")
        ended_at_raw = payload.get("endedAt")
        demo_period_days_raw = payload.get("demoPeriodDays")

        if not isinstance(started_at_raw, str) or not started_at_raw:
            raise RetryableHypothesisError(
                status=400,
                title="Bad Request",
                detail="payload.startedAt is missing or not a string.",
                reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
                trace=envelope.trace,
                retryable=False,
            )
        if not isinstance(ended_at_raw, str) or not ended_at_raw:
            raise RetryableHypothesisError(
                status=400,
                title="Bad Request",
                detail="payload.endedAt is missing or not a string.",
                reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
                trace=envelope.trace,
                retryable=False,
            )

        try:
            started_at = datetime.datetime.fromisoformat(started_at_raw)
        except ValueError as error:
            raise RetryableHypothesisError(
                status=400,
                title="Bad Request",
                detail=f"payload.startedAt is not a valid ISO8601 datetime: {started_at_raw!r}",
                reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
                trace=envelope.trace,
                retryable=False,
            ) from error

        try:
            ended_at = datetime.datetime.fromisoformat(ended_at_raw)
        except ValueError as error:
            raise RetryableHypothesisError(
                status=400,
                title="Bad Request",
                detail=f"payload.endedAt is not a valid ISO8601 datetime: {ended_at_raw!r}",
                reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
                trace=envelope.trace,
                retryable=False,
            ) from error

        demo_period_days = int(demo_period_days_raw) if isinstance(demo_period_days_raw, (int, float)) else 0

        return DemoWindow(
            started_at=started_at,
            ended_at=ended_at,
            demo_period_days=demo_period_days,
        )

    def _record_demo_failure(
        self,
        hypothesis_identifier: str,
        symbol: str,
        demo_window: DemoWindow,
        trace: str,
    ) -> None:
        """Record a demo failure in the failure knowledge base."""
        markdown_summary = (
            f"## Demo Failure\n\n"
            f"- **Hypothesis**: `{hypothesis_identifier}`\n"
            f"- **Symbol**: `{symbol}`\n"
            f"- **Trace**: `{trace}`\n\n"
            f"### Demo Window\n\n"
            f"| Field | Value |\n"
            f"|-------|-------|\n"
            f"| Started At | {demo_window.started_at.isoformat()} |\n"
            f"| Ended At | {demo_window.ended_at.isoformat()} |\n"
            f"| Period Days | {demo_window.demo_period_days} |\n\n"
            f"Demo run completed but hypothesis was not promotable."
        )
        failure_summary = FailureSummary(
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            markdown_summary=markdown_summary,
        )
        self._failure_knowledge_repository.persist(failure_summary)

    def _update_hypothesis_status_to_demo(self, hypothesis_identifier: str, trace: str) -> None:
        """Transition hypothesis to demo status (called externally when demo run starts)."""
        hypothesis = self._hypothesis_repository.find(hypothesis_identifier)
        if hypothesis is None:
            raise RetryableHypothesisError(
                status=404,
                title="Not Found",
                detail=f"Hypothesis '{hypothesis_identifier}' not found.",
                reason_code=ReasonCode.STATE_CONFLICT,
                trace=trace,
                retryable=True,
            )
        if hypothesis.status != HypothesisStatus.BACKTESTED:
            return
        # Status change to DEMO is managed externally (e.g., by a separate start_demo command)
        # This method is a hook for future extension.
