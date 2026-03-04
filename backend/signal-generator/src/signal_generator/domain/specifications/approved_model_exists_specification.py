"""ApprovedModelExistsSpecification."""

from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot


class ApprovedModelExistsSpecification:
    """RULE-SG-002: approved モデルが存在するかどうかを検証する仕様。"""

    def is_satisfied_by(self, model_snapshot: ModelSnapshot | None) -> bool:
        if model_snapshot is None:
            return False
        return model_snapshot.status.is_usable_for_inference()
