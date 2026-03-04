"""Factory for creating FeatureDispatch aggregates."""

from domain.model.feature_dispatch import FeatureDispatch
from domain.model.feature_generation import FeatureGeneration
from domain.value_object.dispatch_decision import DispatchDecision
from domain.value_object.enums import DispatchStatus


class FeatureDispatchFactory:
    """Creates FeatureDispatch aggregates from completed feature generation results."""

    def from_feature_generation(
        self,
        feature_generation: FeatureGeneration,
    ) -> FeatureDispatch:
        return FeatureDispatch(
            identifier=feature_generation.identifier,
            dispatch_status=DispatchStatus.PENDING,
            trace=feature_generation.trace,
            dispatch_decision=DispatchDecision(
                dispatch_status=DispatchStatus.PENDING,
                published_event=None,
                reason_code=None,
            ),
        )
