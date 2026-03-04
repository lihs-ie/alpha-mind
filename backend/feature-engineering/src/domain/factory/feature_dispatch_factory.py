"""Factory for creating FeatureDispatch aggregates."""

from domain.model.feature_dispatch import FeatureDispatch
from domain.model.feature_generation import FeatureGeneration
from domain.value_object.dispatch_decision import DispatchDecision
from domain.value_object.enums import DispatchStatus, FeatureGenerationStatus


class FeatureDispatchFactory:
    """Creates FeatureDispatch aggregates from terminal feature generation results."""

    _TERMINAL_STATUSES = frozenset({FeatureGenerationStatus.GENERATED, FeatureGenerationStatus.FAILED})

    def from_feature_generation(
        self,
        feature_generation: FeatureGeneration,
    ) -> FeatureDispatch:
        if feature_generation.status not in self._TERMINAL_STATUSES:
            raise ValueError(
                f"Cannot create dispatch from non-terminal generation status: {feature_generation.status.value}"
            )

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
