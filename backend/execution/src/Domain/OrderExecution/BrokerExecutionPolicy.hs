module Domain.OrderExecution.BrokerExecutionPolicy (
  isRetryable,
  classifyBrokerError,
) where

import Data.Text (Text)
import Domain.OrderExecution.ReasonCode (ReasonCode (..))

{- | Determine whether a ReasonCode is retryable.
Pure function, no IO. (Must-25)
-}
isRetryable :: ReasonCode -> Bool
isRetryable ExecutionBrokerTimeout = True
isRetryable DependencyTimeout = True
isRetryable InternalError = True
isRetryable _ = False

{- | Classify a broker error description into a ReasonCode.
Maps broker HTTP error strings to domain ReasonCode values.
Pure function, no IO. (Must-25)
-}
classifyBrokerError :: Text -> ReasonCode
classifyBrokerError errorText
  | errorText == "timeout" = ExecutionBrokerTimeout
  | errorText == "rejected" = ExecutionBrokerRejected
  | errorText == "market_closed" = ExecutionMarketClosed
  | errorText == "insufficient_funds" = ExecutionInsufficientFunds
  | otherwise = InternalError
