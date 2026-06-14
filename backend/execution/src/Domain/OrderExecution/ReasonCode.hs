module Domain.OrderExecution.ReasonCode (
  ReasonCode (..),
) where

{- | ReasonCode enumeration for execution bounded context.
Covers broker errors, market state errors, and system errors.
-}
data ReasonCode
  = ExecutionBrokerTimeout
  | ExecutionBrokerRejected
  | ExecutionMarketClosed
  | ExecutionInsufficientFunds
  | IdempotencyDuplicateEvent
  | StateConflict
  | DependencyTimeout
  | InternalError
  deriving stock (Eq, Ord, Show)
