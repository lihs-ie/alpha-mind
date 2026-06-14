module Domain.OrderExecution.BrokerPort (
  BrokerPort (..),
) where

import Data.Text (Text)
import Domain.OrderExecution.Aggregate (ExecutionRequest)
import Domain.OrderExecution.ReasonCode (ReasonCode)

{- | BrokerPort typeclass — port for submitting orders to the broker.
Implementations live in the ACL / Infrastructure layer.
-}
class (Monad m) => BrokerPort m where
  {- | Submit an order to the broker.
  Returns Right brokerOrderIdentifier on success,
  Left reasonCode on broker-side failure.
  -}
  submitBrokerOrder :: ExecutionRequest -> m (Either ReasonCode Text)
