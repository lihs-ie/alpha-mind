{-# LANGUAGE OverloadedRecordDot #-}

{- | Pub/Sub implementation of 'ExecutionEventPublisher' and 'DemoCompletionEventPublisher'.

Must-18: PubSubExecutionEventPublisherT newtype wrapping ReaderT.
Must-19: publishOrdersExecuted builds CloudEvent and publishes to orders.executed topic.
Must-20: publishOrdersExecutionFailed builds CloudEvent and publishes to orders.execution.failed topic.
Must-21: PubSubExecutionEventPublisherEnv holds publisher, executedTopicName,
         executionFailedTopicName, demoCompletedTopicName (injected).
-}
module Infrastructure.Publisher.PubSubExecutionEventPublisher (
  -- * Environment
  PubSubExecutionEventPublisherEnv (..),

  -- * Monad transformer
  PubSubExecutionEventPublisherT (..),
  runPubSubExecutionEventPublisherT,

  -- * Payload types (exported for tests)
  OrdersExecutedPayload (..),
  OrdersExecutionFailedPayload (..),
  HypothesisDemoCompletedPayload (..),

  -- * Pure event builders (exported for contract tests)
  buildOrdersExecutedEvent,
  buildOrdersExecutionFailedEvent,
  buildHypothesisDemoCompletedEvent,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson (ToJSON (..), object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Data.ULID qualified as ULID
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.Aggregate (OrderExecutionIdentifier (..))
import Domain.OrderExecution.DemoRunEvaluation (DemoPerformance (..))
import Domain.OrderExecution.ReasonCode (ReasonCode)
import Infrastructure.Wire.ReasonCodeWire (reasonCodeToWire)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubPublisher, TopicName, publishCloudEvent)
import UseCase.CompleteDemoRun (DemoCompletionEventPublisher (..), DemoRunIdentifier (..), HypothesisIdentifier (..))
import UseCase.ExecuteOrder (BrokerOrder (..), ExecutionEventPublisher (..))

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

data PubSubExecutionEventPublisherEnv = PubSubExecutionEventPublisherEnv
  { publisher :: PubSubPublisher
  , executedTopicName :: TopicName
  , executionFailedTopicName :: TopicName
  , demoCompletedTopicName :: TopicName
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype PubSubExecutionEventPublisherT m a = PubSubExecutionEventPublisherT
  { unPubSubExecutionEventPublisherT :: ReaderT PubSubExecutionEventPublisherEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runPubSubExecutionEventPublisherT ::
  PubSubExecutionEventPublisherEnv ->
  PubSubExecutionEventPublisherT m a ->
  m a
runPubSubExecutionEventPublisherT environment action =
  runReaderT (unPubSubExecutionEventPublisherT action) environment

-- ---------------------------------------------------------------------------
-- Payload types
-- ---------------------------------------------------------------------------

data OrdersExecutedPayload = OrdersExecutedPayload
  { identifier :: Text
  , brokerOrder :: Text
  , executedAt :: UTCTime
  }
  deriving stock (Eq, Show)

instance ToJSON OrdersExecutedPayload where
  toJSON payloadValue =
    object
      [ "identifier" .= payloadValue.identifier
      , "brokerOrder" .= payloadValue.brokerOrder
      , "executedAt" .= payloadValue.executedAt
      ]

newtype OrdersExecutionFailedPayload = OrdersExecutionFailedPayload
  { reasonCode :: Text
  }
  deriving stock (Eq, Show)

instance ToJSON OrdersExecutionFailedPayload where
  toJSON payloadValue =
    object
      [ "reasonCode" .= payloadValue.reasonCode
      ]

{- | Must-19: AsyncAPI hypothesis.demo.completed payload.
All required fields from the AsyncAPI schema are present.
Fields not available from the current DemoCompletionEventPublisher port
(symbol, instrumentType, insiderRisk, startedAt, endedAt, promotable,
requiresComplianceReview, mnpiSelfDeclared) are populated with placeholder
values in the instance below.
TODO: extend DemoCompletionEventPublisher port to supply these fields.
-}
data HypothesisDemoCompletedPayload = HypothesisDemoCompletedPayload
  { identifier :: Text
  , demoRun :: Text
  , symbol :: Text
  , instrumentType :: Text
  , insiderRisk :: Text
  , startedAt :: UTCTime
  , endedAt :: UTCTime
  , demoPeriodDays :: Int
  , promotable :: Bool
  , requiresComplianceReview :: Bool
  , mnpiSelfDeclared :: Bool
  , costAdjustedReturn :: Maybe Double
  , dsr :: Maybe Double
  , pbo :: Maybe Double
  }
  deriving stock (Eq, Show)

instance ToJSON HypothesisDemoCompletedPayload where
  toJSON payloadValue =
    object $
      [ "identifier" .= payloadValue.identifier
      , "demoRun" .= payloadValue.demoRun
      , "symbol" .= payloadValue.symbol
      , "instrumentType" .= payloadValue.instrumentType
      , "insiderRisk" .= payloadValue.insiderRisk
      , "startedAt" .= payloadValue.startedAt
      , "endedAt" .= payloadValue.endedAt
      , "demoPeriodDays" .= payloadValue.demoPeriodDays
      , "promotable" .= payloadValue.promotable
      , "requiresComplianceReview" .= payloadValue.requiresComplianceReview
      , "mnpiSelfDeclared" .= payloadValue.mnpiSelfDeclared
      ]
        <> maybe [] (\costReturn -> ["costAdjustedReturn" .= costReturn]) payloadValue.costAdjustedReturn
        <> maybe [] (\dsrValue -> ["dsr" .= dsrValue]) payloadValue.dsr
        <> maybe [] (\pboValue -> ["pbo" .= pboValue]) payloadValue.pbo

-- ---------------------------------------------------------------------------
-- ExecutionEventPublisher instance
-- ---------------------------------------------------------------------------

instance ExecutionEventPublisher (PubSubExecutionEventPublisherT IO) where
  publishOrdersExecuted executionIdentifier brokerOrderValue executedAtTime traceValue =
    PubSubExecutionEventPublisherT $ do
      environment <- ask
      liftIO $ do
        now <- getCurrentTime
        newEventIdentifier <- ULID.getULID
        let event = buildOrdersExecutedEvent newEventIdentifier now traceValue.value executionIdentifier brokerOrderValue executedAtTime
        _ <- publishCloudEvent environment.publisher environment.executedTopicName event
        pure ()

  publishOrdersExecutionFailed executionIdentifier reasonCode traceValue =
    PubSubExecutionEventPublisherT $ do
      environment <- ask
      liftIO $ do
        now <- getCurrentTime
        newEventIdentifier <- ULID.getULID
        let event = buildOrdersExecutionFailedEvent newEventIdentifier now traceValue.value executionIdentifier reasonCode
        _ <- publishCloudEvent environment.publisher environment.executionFailedTopicName event
        pure ()

-- ---------------------------------------------------------------------------
-- DemoCompletionEventPublisher instance
-- ---------------------------------------------------------------------------

instance DemoCompletionEventPublisher (PubSubExecutionEventPublisherT IO) where
  publishHypothesisDemoCompleted hypothesisIdentifier demoRunIdentifier performance traceValue =
    PubSubExecutionEventPublisherT $ do
      environment <- ask
      liftIO $ do
        now <- getCurrentTime
        newEventIdentifier <- ULID.getULID
        -- TODO: extend DemoCompletionEventPublisher port to supply symbol,
        -- instrumentType, insiderRisk, startedAt, endedAt, promotable,
        -- requiresComplianceReview, and mnpiSelfDeclared from the use-case layer.
        let event =
              buildHypothesisDemoCompletedEvent
                newEventIdentifier
                now
                traceValue.value
                hypothesisIdentifier
                demoRunIdentifier
                ""
                ""
                ""
                now
                now
                False
                False
                False
                performance
        _ <- publishCloudEvent environment.publisher environment.demoCompletedTopicName event
        pure ()

-- ---------------------------------------------------------------------------
-- Pure event builders (exported for contract tests)
-- ---------------------------------------------------------------------------

{- | Build an 'orders.executed' CloudEvent from pure inputs.
Exported so tests can call the real construction path without IO.
-}
buildOrdersExecutedEvent ::
  ULID ->
  UTCTime ->
  ULID ->
  OrderExecutionIdentifier ->
  BrokerOrder ->
  UTCTime ->
  CloudEvent OrdersExecutedPayload
buildOrdersExecutedEvent newEventIdentifier now traceUlid executionIdentifier brokerOrderValue executedAtTime =
  let payload =
        OrdersExecutedPayload
          { identifier = Text.pack (show executionIdentifier.value)
          , brokerOrder = brokerOrderValue.value
          , executedAt = executedAtTime
          }
   in CloudEvent
        { identifier = newEventIdentifier
        , eventType = "orders.executed"
        , occurredAt = now
        , trace = traceUlid
        , schemaVersion = "1.0.0"
        , payload = payload
        }

{- | Build an 'orders.execution.failed' CloudEvent from pure inputs.
Exported so tests can call the real construction path without IO.
-}
buildOrdersExecutionFailedEvent ::
  ULID ->
  UTCTime ->
  ULID ->
  OrderExecutionIdentifier ->
  ReasonCode ->
  CloudEvent OrdersExecutionFailedPayload
buildOrdersExecutionFailedEvent newEventIdentifier now traceUlid _executionIdentifier reasonCode =
  let payload =
        OrdersExecutionFailedPayload
          { reasonCode = reasonCodeToWire reasonCode
          }
   in CloudEvent
        { identifier = newEventIdentifier
        , eventType = "orders.execution.failed"
        , occurredAt = now
        , trace = traceUlid
        , schemaVersion = "1.0.0"
        , payload = payload
        }

{- | Build a 'hypothesis.demo.completed' CloudEvent from pure inputs.

Exported so tests can call the real construction path without IO.
The extra parameters (symbol, instrumentType, insiderRisk, startedAt, endedAt,
promotable, requiresComplianceReview, mnpiSelfDeclared) are required by the
AsyncAPI schema but are not yet available from the port signature.
Pass placeholder values when called from the current instance.
-}
buildHypothesisDemoCompletedEvent ::
  ULID ->
  UTCTime ->
  ULID ->
  HypothesisIdentifier ->
  DemoRunIdentifier ->
  Text ->
  Text ->
  Text ->
  UTCTime ->
  UTCTime ->
  Bool ->
  Bool ->
  Bool ->
  DemoPerformance ->
  CloudEvent HypothesisDemoCompletedPayload
buildHypothesisDemoCompletedEvent
  newEventIdentifier
  now
  traceUlid
  hypothesisIdentifier
  demoRunIdentifier
  symbolValue
  instrumentTypeValue
  insiderRiskValue
  startedAtValue
  endedAtValue
  promotableValue
  requiresComplianceReviewValue
  mnpiSelfDeclaredValue
  performance =
    let payload =
          HypothesisDemoCompletedPayload
            { identifier = Text.pack (show hypothesisIdentifier.value)
            , demoRun = demoRunIdentifier.value
            , symbol = symbolValue
            , instrumentType = instrumentTypeValue
            , insiderRisk = insiderRiskValue
            , startedAt = startedAtValue
            , endedAt = endedAtValue
            , demoPeriodDays = performance.demoPeriodDays
            , promotable = promotableValue
            , requiresComplianceReview = requiresComplianceReviewValue
            , mnpiSelfDeclared = mnpiSelfDeclaredValue
            , costAdjustedReturn = Just performance.costAdjustedReturn
            , dsr = performance.dsr
            , pbo = performance.pbo
            }
     in CloudEvent
          { identifier = newEventIdentifier
          , eventType = "hypothesis.demo.completed"
          , occurredAt = now
          , trace = traceUlid
          , schemaVersion = "1.0.0"
          , payload = payload
          }
