"""Factory for creating FeatureDispatch aggregates."""

from domain.model.feature_dispatch import FeatureDispatch
from domain.value_object.dispatch_decision import DispatchDecision
from domain.value_object.enums import DispatchStatus


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
            dispatch_decision=DispatchDecision(
                dispatch_status=DispatchStatus.PENDING,
                published_event=None,
                reason_code=None,
            ),
        )
