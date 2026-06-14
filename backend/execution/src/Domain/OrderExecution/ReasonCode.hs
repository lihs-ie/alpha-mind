module Domain.OrderExecution.ReasonCode (
  ReasonCode (..),
) where

{- | Must-06: execution 関連 ReasonCode 列挙。
error-codes.json（owner=execution / all）および execution_ドメインモデル設計 §5.1 §6.2 に準拠。
-}
data ReasonCode
  = -- | EXECUTION_BROKER_TIMEOUT（retryable）。
    ExecutionBrokerTimeout
  | -- | EXECUTION_BROKER_REJECTED（非 retryable）。
    ExecutionBrokerRejected
  | -- | EXECUTION_MARKET_CLOSED（非 retryable）。
    ExecutionMarketClosed
  | -- | EXECUTION_INSUFFICIENT_FUNDS（非 retryable）。
    ExecutionInsufficientFunds
  | -- | DEPENDENCY_UNAVAILABLE（retryable）。
    DependencyUnavailable
  | -- | DEPENDENCY_TIMEOUT（retryable）。
    DependencyTimeout
  | -- | IDEMPOTENCY_DUPLICATE_EVENT（重複イベント・副作用なし）。
    IdempotencyDuplicateEvent
  | -- | STATE_CONFLICT（終端状態への再実行）。
    StateConflict
  deriving stock (Eq, Ord, Show)
