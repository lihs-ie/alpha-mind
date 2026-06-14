{- | Wire-format serialization for execution 'ReasonCode'.

error-codes.json and AsyncAPI require SCREAMING_SNAKE_CASE values.
Using @show@ on the Haskell constructor produces PascalCase, which
breaks the downstream contract.  This module provides the single
authoritative mapping.
-}
module Infrastructure.Wire.ReasonCodeWire (
  reasonCodeToWire,
) where

import Data.Text (Text)
import Domain.OrderExecution.ReasonCode (ReasonCode (..))

{- | Serialize a 'ReasonCode' to the SCREAMING_SNAKE_CASE wire value
mandated by error-codes.json and the AsyncAPI schema.
-}
reasonCodeToWire :: ReasonCode -> Text
reasonCodeToWire ExecutionBrokerTimeout = "EXECUTION_BROKER_TIMEOUT"
reasonCodeToWire ExecutionBrokerRejected = "EXECUTION_BROKER_REJECTED"
reasonCodeToWire ExecutionMarketClosed = "EXECUTION_MARKET_CLOSED"
reasonCodeToWire ExecutionInsufficientFunds = "EXECUTION_INSUFFICIENT_FUNDS"
reasonCodeToWire IdempotencyDuplicateEvent = "IDEMPOTENCY_DUPLICATE_EVENT"
reasonCodeToWire StateConflict = "STATE_CONFLICT"
reasonCodeToWire DependencyTimeout = "DEPENDENCY_TIMEOUT"
reasonCodeToWire InternalError = "INTERNAL_ERROR"
