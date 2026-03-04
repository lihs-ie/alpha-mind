"""Specification for RULE-FE-002: source status health check."""

from src.domain.value_object.enums import SourceStatusValue
from src.domain.value_object.source_status import SourceStatus


class SourceStatusHealthySpecification:
    """Validates that both JP and US market data sources are healthy (ok)."""

    def is_satisfied_by(self, source_status: SourceStatus) -> bool:
        return source_status.jp == SourceStatusValue.OK and source_status.us == SourceStatusValue.OK
