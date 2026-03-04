"""Factory for creating FeatureGeneration aggregates."""

import datetime

from domain.event.domain_events import FeatureGenerationStarted
from domain.model.feature_generation import FeatureGeneration
from domain.specification.market_payload_integrity import MarketPayloadIntegritySpecification
from domain.specification.source_status_healthy import SourceStatusHealthySpecification
from domain.value_object.enums import FeatureGenerationStatus, ReasonCode
from domain.value_object.failure_detail import FailureDetail
from domain.value_object.market_snapshot import MarketSnapshot


class FeatureGenerationFactory:
    """Creates FeatureGeneration aggregates from incoming market.collected events."""

    def from_market_collected_event(
        self,
        identifier: str,
        market: MarketSnapshot,
        trace: str,
    ) -> FeatureGeneration:
        # RULE-FE-001: 必須フィールド欠損時は生成開始しない
        integrity_specification = MarketPayloadIntegritySpecification()
        if not integrity_specification.is_satisfied_by(market):
            raise ValueError("RULE-FE-001: market payload integrity check failed - required fields missing")

        generation = FeatureGeneration(
            identifier=identifier,
            status=FeatureGenerationStatus.PENDING,
            market=market,
            trace=trace,
        )

        generation.record_domain_event(
            FeatureGenerationStarted(
                identifier=identifier,
                target_date=market.target_date,
                trace=trace,
                occurred_at=datetime.datetime.now(tz=datetime.UTC),
            )
        )

        # RULE-FE-002: source status が unhealthy の場合は即時 FAILED に遷移
        source_health_specification = SourceStatusHealthySpecification()
        if not source_health_specification.is_satisfied_by(market.source_status):
            generation.fail(
                failure_detail=FailureDetail(
                    reason_code=ReasonCode.DEPENDENCY_UNAVAILABLE,
                    detail="Source status is not healthy",
                    retryable=True,
                ),
                processed_at=datetime.datetime.now(tz=datetime.UTC),
            )

        return generation
