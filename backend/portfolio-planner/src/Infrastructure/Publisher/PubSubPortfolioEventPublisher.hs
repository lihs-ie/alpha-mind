{-# LANGUAGE OverloadedRecordDot #-}

{- | Pub/Sub publisher for portfolio-planner events.

Must-05: PubSubPortfolioEventPublisherT newtype wrapping ReaderT.
Must-05: buildOrdersProposedEvent and buildOrdersProposalFailedEvent build CloudEvent values.
Must-05: PubSubPortfolioEventPublisherEnv holds publisher, proposedTopicName, failedTopicName.

Publishes:
- orders.proposed: CloudEvent with payload {identifier, orders, orderCount, trace, occurredAt}
- orders.proposal.failed: CloudEvent with payload {identifier, reasonCode, trace, occurredAt}
-}
module Infrastructure.Publisher.PubSubPortfolioEventPublisher (
  -- * Environment
  PubSubPortfolioEventPublisherEnv (..),

  -- * Monad transformer
  PubSubPortfolioEventPublisherT (..),
  runPubSubPortfolioEventPublisherT,

  -- * Payload types (exported for tests)
  OrderItemPayload (..),
  OrdersProposedPayload (..),
  OrdersProposalFailedPayload (..),

  -- * Pure event builders (exported for contract tests)
  buildOrdersProposedEvent,
  buildOrdersProposalFailedEvent,

  -- * IO publish actions (used by presentation layer)
  publishOrdersProposed,
  publishOrdersProposalFailed,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson (ToJSON (..), object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Data.ULID qualified as ULID
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Aggregate (
  OrderProposal,
  OrderProposalIdentifier (..),
  Side (..),
 )
import Domain.OrderProposal.ProposalDispatch (
  ProposalDispatch,
  ProposalDispatchIdentifier (..),
 )
import Domain.OrderProposal.ReasonCode (ReasonCode)
import Infrastructure.Wire.ReasonCodeWire (reasonCodeToWire)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubPublisher, TopicName, publishCloudEvent)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

data PubSubPortfolioEventPublisherEnv = PubSubPortfolioEventPublisherEnv
  { publisher :: PubSubPublisher
  , proposedTopicName :: TopicName
  , failedTopicName :: TopicName
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype PubSubPortfolioEventPublisherT m a = PubSubPortfolioEventPublisherT
  { unPubSubPortfolioEventPublisherT :: ReaderT PubSubPortfolioEventPublisherEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runPubSubPortfolioEventPublisherT ::
  PubSubPortfolioEventPublisherEnv ->
  PubSubPortfolioEventPublisherT m a ->
  m a
runPubSubPortfolioEventPublisherT environment action =
  runReaderT (unPubSubPortfolioEventPublisherT action) environment

-- ---------------------------------------------------------------------------
-- Payload types
-- ---------------------------------------------------------------------------

data OrderItemPayload = OrderItemPayload
  { identifier :: Text
  , symbol :: Text
  , side :: Text
  , qty :: Text
  }
  deriving stock (Eq, Show)

instance ToJSON OrderItemPayload where
  toJSON item =
    object
      [ "identifier" .= item.identifier
      , "symbol" .= item.symbol
      , "side" .= item.side
      , "qty" .= item.qty
      ]

data OrdersProposedPayload = OrdersProposedPayload
  { identifier :: Text
  , orders :: [OrderItemPayload]
  , orderCount :: Int
  , trace :: Text
  }
  deriving stock (Eq, Show)

instance ToJSON OrdersProposedPayload where
  toJSON payloadValue =
    object
      [ "identifier" .= payloadValue.identifier
      , "orders" .= payloadValue.orders
      , "orderCount" .= payloadValue.orderCount
      , "trace" .= payloadValue.trace
      ]

data OrdersProposalFailedPayload = OrdersProposalFailedPayload
  { identifier :: Text
  , reasonCode :: Text
  , trace :: Text
  }
  deriving stock (Eq, Show)

instance ToJSON OrdersProposalFailedPayload where
  toJSON payloadValue =
    object
      [ "identifier" .= payloadValue.identifier
      , "reasonCode" .= payloadValue.reasonCode
      , "trace" .= payloadValue.trace
      ]

-- ---------------------------------------------------------------------------
-- Pure event builders (exported for contract tests)
-- ---------------------------------------------------------------------------

{- | Build an 'orders.proposed' CloudEvent from pure inputs.
Exported so tests can call the real construction path without IO.
-}
buildOrdersProposedEvent ::
  ULID ->
  UTCTime ->
  ULID ->
  ProposalDispatch ->
  [OrderProposal] ->
  CloudEvent OrdersProposedPayload
buildOrdersProposedEvent newEventIdentifier now traceUlid dispatch orders =
  let orderItems = map toOrderItemPayload orders
      ProposalDispatchIdentifier dispatchUlid = dispatch.identifier
      payloadValue =
        OrdersProposedPayload
          { identifier = Text.pack (show dispatchUlid)
          , orders = orderItems
          , orderCount = length orders
          , trace = Text.pack (show traceUlid)
          }
   in CloudEvent
        { identifier = newEventIdentifier
        , eventType = "orders.proposed"
        , occurredAt = now
        , trace = traceUlid
        , schemaVersion = "1.0.0"
        , payload = payloadValue
        }

{- | Build an 'orders.proposal.failed' CloudEvent from pure inputs.
Exported so tests can call the real construction path without IO.
-}
buildOrdersProposalFailedEvent ::
  ULID ->
  UTCTime ->
  ULID ->
  ProposalDispatchIdentifier ->
  ReasonCode ->
  CloudEvent OrdersProposalFailedPayload
buildOrdersProposalFailedEvent newEventIdentifier now traceUlid dispatchIdentifier reasonCode =
  let ProposalDispatchIdentifier dispatchUlid = dispatchIdentifier
      payloadValue =
        OrdersProposalFailedPayload
          { identifier = Text.pack (show dispatchUlid)
          , reasonCode = reasonCodeToWire reasonCode
          , trace = Text.pack (show traceUlid)
          }
   in CloudEvent
        { identifier = newEventIdentifier
        , eventType = "orders.proposal.failed"
        , occurredAt = now
        , trace = traceUlid
        , schemaVersion = "1.0.0"
        , payload = payloadValue
        }

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

sideToText :: Side -> Text
sideToText Buy = "BUY"
sideToText Sell = "SELL"

toOrderItemPayload :: OrderProposal -> OrderItemPayload
toOrderItemPayload proposal =
  let OrderProposalIdentifier identifierUlid = proposal.identifier
   in OrderItemPayload
        { identifier = Text.pack (show identifierUlid)
        , symbol = proposal.symbol
        , side = sideToText proposal.side
        , qty = Text.pack (show proposal.qty)
        }

-- ---------------------------------------------------------------------------
-- IO publish actions (used by presentation layer - Issue #40)
-- ---------------------------------------------------------------------------

{- | Publish an 'orders.proposed' event to Pub/Sub.
Called by the presentation layer after a successful proposal.
-}
publishOrdersProposed ::
  ProposalDispatch ->
  [OrderProposal] ->
  Trace ->
  PubSubPortfolioEventPublisherT IO ()
publishOrdersProposed dispatch orders traceValue = PubSubPortfolioEventPublisherT $ do
  environment <- ask
  liftIO $ do
    now <- getCurrentTime
    let Trace traceUlid = traceValue
    newEventIdentifier <- ULID.getULID
    let event = buildOrdersProposedEvent newEventIdentifier now traceUlid dispatch orders
    _ <- publishCloudEvent environment.publisher environment.proposedTopicName event
    pure ()

{- | Publish an 'orders.proposal.failed' event to Pub/Sub.
Called by the presentation layer after a failed proposal.
-}
publishOrdersProposalFailed ::
  ProposalDispatchIdentifier ->
  ReasonCode ->
  Trace ->
  PubSubPortfolioEventPublisherT IO ()
publishOrdersProposalFailed dispatchIdentifier reasonCode traceValue = PubSubPortfolioEventPublisherT $ do
  environment <- ask
  liftIO $ do
    now <- getCurrentTime
    let Trace traceUlid = traceValue
    newEventIdentifier <- ULID.getULID
    let event = buildOrdersProposalFailedEvent newEventIdentifier now traceUlid dispatchIdentifier reasonCode
    _ <- publishCloudEvent environment.publisher environment.failedTopicName event
    pure ()
