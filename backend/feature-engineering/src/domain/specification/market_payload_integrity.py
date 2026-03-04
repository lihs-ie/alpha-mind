"""Specification for RULE-FE-001: market.collected payload integrity check."""

from domain.value_object.market_snapshot import MarketSnapshot


class MarketPayloadIntegritySpecification:
    """Validates that all required fields in MarketSnapshot are present and non-empty.

    RULE-FE-001: market.collected の必須項目欠損時は生成開始しない
    Required fields: targetDate, storagePath, sourceStatus
    """

    def is_satisfied_by(self, market: MarketSnapshot) -> bool:
        if market.target_date is None:
            return False
        if not market.storage_path:
            return False
        return market.source_status is not None
