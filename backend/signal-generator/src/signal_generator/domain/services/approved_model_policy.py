"""ApprovedModelPolicy domain service."""

from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot


class ApprovedModelPolicy:
    """RULE-SG-002: approved モデル解決可否を判定するドメインポリシー。

    IO処理を含まず、純粋なドメインロジックのみを担当する。
    """

    def is_satisfied_by(self, model_snapshot: ModelSnapshot | None) -> bool:
        """モデルが approved かどうかを判定する。"""
        if model_snapshot is None:
            return False
        return model_snapshot.status.is_usable_for_inference()

    def reason_code(self, model_snapshot: ModelSnapshot | None) -> ReasonCode | None:
        """ポリシー違反の理由コードを返す。満足している場合は None を返す。

        RULE-SG-002: approved モデルが存在しない場合、またはモデルが非承認の場合は
        MODEL_NOT_APPROVED を返す。設計書の状態遷移表に基づき、モデル未存在と
        モデル非承認を同一の reasonCode で扱う。
        """
        if self.is_satisfied_by(model_snapshot):
            return None
        return ReasonCode.MODEL_NOT_APPROVED
