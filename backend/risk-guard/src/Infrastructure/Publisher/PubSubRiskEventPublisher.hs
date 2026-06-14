{-# LANGUAGE OverloadedRecordDot #-}

{- | Pub/Sub implementation of 'RiskEventPublisher'.

Must-21: PubSubRiskEventPublisherT newtype wrapping ReaderT.
Must-22: PubSubRiskEventPublisherEnv holds publisher, approvedTopicName, rejectedTopicName.
Must-23: publishOrdersApproved publishes to orders.approved topic.
Must-24: publishOrdersRejected publishes to orders.rejected topic.
Must-25: buildOrdersApprovedEvent and buildOrdersRejectedEvent are pure, exported.
-}
module Infrastructure.Publisher.PubSubRiskEventPublisher (
  -- * Environment
  PubSubRiskEventPublisherEnv (..),

  -- * Monad transformer
  PubSubRiskEventPublisherT (..),
  runPubSubRiskEventPublisherT,

  -- * Payload types (exported for tests)
  OrdersApprovedEventPayload (..),
  OrdersRejectedEventPayload (..),

  -- * Pure event builders (exported for contract tests — TST-INFRA-005/006)
  buildOrdersApprovedEvent,
  buildOrdersRejectedEvent,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson (ToJSON (..), object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Data.ULID qualified as ULID
import Domain.RiskAssessment (Trace (..))
import Domain.RiskAssessment.Aggregate (
  OrdersApprovedPayload (..),
  OrdersRejectedPayload (..),
  RiskEventPublisher (..),
 )
import Domain.RiskAssessment.ValueObjects (OrderRiskAssessmentIdentifier (..))
import Infrastructure.Wire.ReasonCodeWire (
  operatorActionReasonCodeToWire,
  reasonCodeToWire,
 )
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubPublisher, TopicName, publishCloudEvent)

-- ---------------------------------------------------------------------------
-- Environment (Must-22)
-- ---------------------------------------------------------------------------

data PubSubRiskEventPublisherEnv = PubSubRiskEventPublisherEnv
  { publisher :: PubSubPublisher
  , approvedTopicName :: TopicName
  , rejectedTopicName :: TopicName
  }

-- ---------------------------------------------------------------------------
-- Monad transformer (Must-21)
-- ---------------------------------------------------------------------------

newtype PubSubRiskEventPublisherT m a = PubSubRiskEventPublisherT
  { unPubSubRiskEventPublisherT :: ReaderT PubSubRiskEventPublisherEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runPubSubRiskEventPublisherT ::
  PubSubRiskEventPublisherEnv ->
  PubSubRiskEventPublisherT m a ->
  m a
runPubSubRiskEventPublisherT environment action =
  runReaderT (unPubSubRiskEventPublisherT action) environment

-- ---------------------------------------------------------------------------
-- Payload types (Must-23/24, AsyncAPI schema compliance)
-- ---------------------------------------------------------------------------

-- | Payload for @orders.approved@ CloudEvent. Must-23.
data OrdersApprovedEventPayload = OrdersApprovedEventPayload
  { identifier :: Text
  -- ^ Order risk assessment identifier (ULID string).
  , decision :: Text
  -- ^ Always @"approved"@.
  , reasonCode :: Maybe Text
  -- ^ Optional reason code wire value.
  , actionReasonCode :: Maybe Text
  -- ^ Optional operator action reason code wire value.
  }
  deriving stock (Eq, Show)

instance ToJSON OrdersApprovedEventPayload where
  toJSON payloadValue =
    object $
      [ "identifier" .= payloadValue.identifier
      , "decision" .= payloadValue.decision
      ]
        <> maybe [] (\code -> ["reasonCode" .= code]) payloadValue.reasonCode
        <> maybe [] (\code -> ["actionReasonCode" .= code]) payloadValue.actionReasonCode

-- | Payload for @orders.rejected@ CloudEvent. Must-24.
data OrdersRejectedEventPayload = OrdersRejectedEventPayload
  { identifier :: Text
  -- ^ Order risk assessment identifier (ULID string).
  , decision :: Text
  -- ^ Always @"rejected"@.
  , reasonCode :: Text
  -- ^ Required reason code wire value.
  }
  deriving stock (Eq, Show)

instance ToJSON OrdersRejectedEventPayload where
  toJSON payloadValue =
    object
      [ "identifier" .= payloadValue.identifier
      , "decision" .= payloadValue.decision
      , "reasonCode" .= payloadValue.reasonCode
      ]

-- ---------------------------------------------------------------------------
-- RiskEventPublisher instance (Must-21)
-- ---------------------------------------------------------------------------

instance RiskEventPublisher (PubSubRiskEventPublisherT IO) where
  -- Must-23
  publishOrdersApproved approvedPayload =
    PubSubRiskEventPublisherT $ do
      environment <- ask
      liftIO $ do
        now <- getCurrentTime
        newEventIdentifier <- ULID.getULID
        let event = buildOrdersApprovedEvent newEventIdentifier now approvedPayload
        _ <- publishCloudEvent environment.publisher environment.approvedTopicName event
        pure ()

  -- Must-24
  publishOrdersRejected rejectedPayload =
    PubSubRiskEventPublisherT $ do
      environment <- ask
      liftIO $ do
        now <- getCurrentTime
        newEventIdentifier <- ULID.getULID
        let event = buildOrdersRejectedEvent newEventIdentifier now rejectedPayload
        _ <- publishCloudEvent environment.publisher environment.rejectedTopicName event
        pure ()

-- ---------------------------------------------------------------------------
-- Pure event builders (Must-25, exported for TST-INFRA-005/006)
-- ---------------------------------------------------------------------------

{- | Build an @orders.approved@ CloudEvent from pure inputs. Must-25.
Exported so tests can call the real construction path without IO.
-}
buildOrdersApprovedEvent ::
  ULID ->
  UTCTime ->
  OrdersApprovedPayload ->
  CloudEvent OrdersApprovedEventPayload
buildOrdersApprovedEvent newEventIdentifier now approvedPayload =
  let OrderRiskAssessmentIdentifier assessmentIdUlid = approvedPayload.identifier
      Trace traceUlid = approvedPayload.trace
      payload =
        OrdersApprovedEventPayload
          { identifier = identifierText assessmentIdUlid
          , decision = "approved"
          , reasonCode = fmap reasonCodeToWire approvedPayload.reasonCode
          , actionReasonCode = fmap operatorActionReasonCodeToWire approvedPayload.actionReasonCode
          }
   in CloudEvent
        { identifier = newEventIdentifier
        , eventType = "orders.approved"
        , occurredAt = now
        , trace = traceUlid
        , schemaVersion = "1.0.0"
        , payload = payload
        }

{- | Build an @orders.rejected@ CloudEvent from pure inputs. Must-25.
Exported so tests can call the real construction path without IO.
-}
buildOrdersRejectedEvent ::
  ULID ->
  UTCTime ->
  OrdersRejectedPayload ->
  CloudEvent OrdersRejectedEventPayload
buildOrdersRejectedEvent newEventIdentifier now rejectedPayload =
  let OrderRiskAssessmentIdentifier assessmentIdUlid = rejectedPayload.identifier
      Trace traceUlid = rejectedPayload.trace
      payload =
        OrdersRejectedEventPayload
          { identifier = identifierText assessmentIdUlid
          , decision = "rejected"
          , reasonCode = reasonCodeToWire rejectedPayload.reasonCode
          }
   in CloudEvent
        { identifier = newEventIdentifier
        , eventType = "orders.rejected"
        , occurredAt = now
        , trace = traceUlid
        , schemaVersion = "1.0.0"
        , payload = payload
        }

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

identifierText :: ULID -> Text
identifierText ulid = Text.pack (show ulid)
