"""Domain service interface for RULE-FE-006: featureVersion unique numbering."""

import datetime
from abc import ABC, abstractmethod


class FeatureVersionGenerator(ABC):
    """Generates unique, immutable feature version identifiers.

    RULE-FE-006: featureVersion は一意採番・変更禁止
    Implementations must guarantee uniqueness per target_date.
    """

    @abstractmethod
    def generate(self, target_date: datetime.date) -> str: ...
