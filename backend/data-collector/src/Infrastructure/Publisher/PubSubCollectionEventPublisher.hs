{-# LANGUAGE OverloadedRecordDot #-}

{- | Pub/Sub implementation of 'CollectionEventPublisher'.

Must-18: PubSubCollectionEventPublisherT newtype wrapping ReaderT.
Must-19: publishMarketCollected builds CloudEvent and publishes to market.collected topic.
Must-20: publishMarketCollectFailed builds CloudEvent and publishes to market.collect.failed topic.
Must-21: PubSubCollectionEventPublisherEnv holds publisher, collectedTopicName, failedTopicName (injected).
-}
module Infrastructure.Publisher.PubSubCollectionEventPublisher (
  -- * Environment
  PubSubCollectionEventPublisherEnv (..),

  -- * Monad transformer
  PubSubCollectionEventPublisherT (..),
  runPubSubCollectionEventPublisherT,

  -- * Payload types (exported for tests)
  MarketCollectedPayload (..),
  MarketCollectFailedPayload (..),
  SourceStatusPayload (..),

  -- * Pure event builders (exported for contract tests)
  buildMarketCollectedEvent,
  buildMarketCollectFailedEvent,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson (ToJSON (..), object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Data.ULID qualified as ULID
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (
  CollectedArtifact,
  MarketSourceStatus (..),
  SourceStatus (..),
  collectedArtifactSourceStatus,
  collectedArtifactStoragePath,
  collectedArtifactTargetDate,
 )
import Domain.MarketCollection.ReasonCode (ReasonCode)
import Infrastructure.Wire.ReasonCodeWire (reasonCodeToWire)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubPublisher, TopicName, publishCloudEvent)
import UseCase.CollectMarketData (CollectionEventPublisher (..))

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

data PubSubCollectionEventPublisherEnv = PubSubCollectionEventPublisherEnv
  { publisher :: PubSubPublisher
  , collectedTopicName :: TopicName
  , failedTopicName :: TopicName
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype PubSubCollectionEventPublisherT m a = PubSubCollectionEventPublisherT
  { unPubSubCollectionEventPublisherT :: ReaderT PubSubCollectionEventPublisherEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runPubSubCollectionEventPublisherT ::
  PubSubCollectionEventPublisherEnv ->
  PubSubCollectionEventPublisherT m a ->
  m a
runPubSubCollectionEventPublisherT environment action =
  runReaderT (unPubSubCollectionEventPublisherT action) environment

-- ---------------------------------------------------------------------------
-- Payload types
-- ---------------------------------------------------------------------------

data SourceStatusPayload = SourceStatusPayload
  { jp :: Text
  , us :: Text
  }
  deriving stock (Eq, Show)

instance ToJSON SourceStatusPayload where
  toJSON statusPayload =
    object
      [ "jp" .= statusPayload.jp
      , "us" .= statusPayload.us
      ]

data MarketCollectedPayload = MarketCollectedPayload
  { targetDate :: Text
  , storagePath :: Text
  , sourceStatus :: SourceStatusPayload
  }
  deriving stock (Eq, Show)

instance ToJSON MarketCollectedPayload where
  toJSON payloadValue =
    object
      [ "targetDate" .= payloadValue.targetDate
      , "storagePath" .= payloadValue.storagePath
      , "sourceStatus" .= payloadValue.sourceStatus
      ]

data MarketCollectFailedPayload = MarketCollectFailedPayload
  { reasonCode :: Text
  , detail :: Maybe Text
  }
  deriving stock (Eq, Show)

instance ToJSON MarketCollectFailedPayload where
  toJSON payloadValue =
    object $
      ["reasonCode" .= payloadValue.reasonCode]
        <> maybe [] (\detailText -> ["detail" .= detailText]) payloadValue.detail

-- ---------------------------------------------------------------------------
-- CollectionEventPublisher instance
-- ---------------------------------------------------------------------------

instance CollectionEventPublisher (PubSubCollectionEventPublisherT IO) where
  -- Must-19
  publishMarketCollected _collectionIdentifier artifact traceValue =
    PubSubCollectionEventPublisherT $ do
      environment <- ask
      liftIO $ do
        now <- getCurrentTime
        newEventIdentifier <- ULID.getULID
        let event = buildMarketCollectedEvent newEventIdentifier now traceValue.value artifact
        _ <- publishCloudEvent environment.publisher environment.collectedTopicName event
        pure ()

  -- Must-20
  publishMarketCollectFailed _collectionIdentifier reasonCode maybeDetail traceValue =
    PubSubCollectionEventPublisherT $ do
      environment <- ask
      liftIO $ do
        now <- getCurrentTime
        newEventIdentifier <- ULID.getULID
        let event = buildMarketCollectFailedEvent newEventIdentifier now traceValue.value reasonCode maybeDetail
        _ <- publishCloudEvent environment.publisher environment.failedTopicName event
        pure ()

-- ---------------------------------------------------------------------------
-- Pure event builders (exported for contract tests — TC-INFRA-006/007)
-- ---------------------------------------------------------------------------

{- | Build a 'market.collected' CloudEvent from pure inputs.
Exported so tests can call the real construction path without IO.
-}
buildMarketCollectedEvent ::
  ULID ->
  UTCTime ->
  ULID ->
  CollectedArtifact ->
  CloudEvent MarketCollectedPayload
buildMarketCollectedEvent newEventIdentifier now traceUlid artifact =
  let SourceStatus jpStatus usStatus = collectedArtifactSourceStatus artifact
      payload =
        MarketCollectedPayload
          { targetDate = Text.pack (show (collectedArtifactTargetDate artifact))
          , storagePath = collectedArtifactStoragePath artifact
          , sourceStatus =
              SourceStatusPayload
                { jp = marketSourceStatusToText jpStatus
                , us = marketSourceStatusToText usStatus
                }
          }
   in CloudEvent
        { identifier = newEventIdentifier
        , eventType = "market.collected"
        , occurredAt = now
        , trace = traceUlid
        , schemaVersion = "1.0.0"
        , payload = payload
        }

{- | Build a 'market.collect.failed' CloudEvent from pure inputs.
Exported so tests can call the real construction path without IO.
-}
buildMarketCollectFailedEvent ::
  ULID ->
  UTCTime ->
  ULID ->
  ReasonCode ->
  Maybe Text ->
  CloudEvent MarketCollectFailedPayload
buildMarketCollectFailedEvent newEventIdentifier now traceUlid reasonCode maybeDetail =
  let payload =
        MarketCollectFailedPayload
          { reasonCode = reasonCodeToText reasonCode
          , detail = maybeDetail
          }
   in CloudEvent
        { identifier = newEventIdentifier
        , eventType = "market.collect.failed"
        , occurredAt = now
        , trace = traceUlid
        , schemaVersion = "1.0.0"
        , payload = payload
        }

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

marketSourceStatusToText :: MarketSourceStatus -> Text
marketSourceStatusToText Ok = "ok"
marketSourceStatusToText SourceFailed = "failed"

reasonCodeToText :: ReasonCode -> Text
reasonCodeToText = reasonCodeToWire
