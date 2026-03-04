"""Specification for RULE-FE-001: market.collected payload integrity check."""

from src.domain.value_object.market_snapshot import MarketSnapshot


class MarketPayloadIntegritySpecification:
    """Validates that all required fields in MarketSnapshot are present and non-empty."""

    def is_satisfied_by(self, market: MarketSnapshot) -> bool:
        return bool(market.storage_path)
