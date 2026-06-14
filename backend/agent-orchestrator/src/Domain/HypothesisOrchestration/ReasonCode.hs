module Domain.HypothesisOrchestration.ReasonCode (
  ReasonCode (..),
) where

{- | Must-34: 6値の ReasonCode 列挙型。
RULE-AO-008: RESOURCE_NOT_FOUND / REQUEST_VALIDATION_FAILED は非再試行。
DEPENDENCY_TIMEOUT / DEPENDENCY_UNAVAILABLE は一時障害（再試行可）。
STATE_CONFLICT は冪等性違反。
IDEMPOTENCY_DUPLICATE_EVENT は重複イベント。
-}
data ReasonCode
  = -- | 要求したリソースが存在しない（非再試行）
    ResourceNotFound
  | -- | 入力バリデーション失敗（非再試行）
    RequestValidationFailed
  | -- | 集約の状態が操作を受け付けられない
    StateConflict
  | -- | 同一識別子のイベントが既に処理済み
    IdempotencyDuplicateEvent
  | -- | 依存サービスがタイムアウト（再試行可）
    DependencyTimeout
  | -- | 依存サービスが利用不可（再試行可）
    DependencyUnavailable
  deriving stock (Eq, Ord, Show)
