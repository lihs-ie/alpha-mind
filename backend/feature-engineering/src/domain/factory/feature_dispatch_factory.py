"""Factory for creating FeatureDispatch aggregates."""

from src.domain.model.feature_dispatch import FeatureDispatch
from src.domain.value_object.enums import DispatchStatus


class FeatureDispatchFactory:
    """Creates FeatureDispatch aggregates from completed feature generation results."""

    def from_feature_generation(
        self,
        identifier: str,
        trace: str,
    ) -> FeatureDispatch:
        return FeatureDispatch(
            identifier=identifier,
            dispatch_status=DispatchStatus.PENDING,
            trace=trace,
        )
