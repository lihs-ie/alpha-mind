"""Factory for creating FeatureGeneration aggregates."""

import datetime

from domain.event.domain_events import FeatureGenerationStarted
from domain.model.feature_generation import FeatureGeneration
from domain.value_object.enums import FeatureGenerationStatus
from domain.value_object.market_snapshot import MarketSnapshot


class FeatureGenerationFactory:
    """Creates FeatureGeneration aggregates from incoming market.collected events."""

    def from_market_collected_event(
        self,
        identifier: str,
        market: MarketSnapshot,
        trace: str,
    ) -> FeatureGeneration:
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

        return generation
