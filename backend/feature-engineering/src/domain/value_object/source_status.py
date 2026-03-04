"""SourceStatus value object - market data source collection status."""

from dataclasses import dataclass

from src.domain.value_object.enums import SourceStatusValue


@dataclass(frozen=True)
class SourceStatus:
    """Collection status for JP and US market data sources."""

    jp: SourceStatusValue
    us: SourceStatusValue
