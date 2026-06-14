{-# LANGUAGE OverloadedRecordDot #-}

{- | Pub/Sub implementation of 'InsightCollectionEventPublisher'.

Must-INFRA-019: PubSubInsightEventPublisherT newtype wrapping ReaderT.
Must-INFRA-020: publishInsightCollected builds CloudEvent and publishes to insight.collected topic.
Must-INFRA-021: publishInsightCollectFailed builds CloudEvent and publishes to insight.collect.failed topic.
Must-INFRA-022: PubSubInsightEventPublisherEnv holds publisher, collectedTopicName, failedTopicName.
-}
module Infrastructure.Publisher.PubSubInsightEventPublisher (
  -- * Environment
  PubSubInsightEventPublisherEnv (..),

  -- * Monad transformer
  PubSubInsightEventPublisherT (..),
  runPubSubInsightEventPublisherT,

  -- * Payload types (exported for tests)
  InsightCollectedPayload (..),
  InsightCollectFailedPayload (..),
  SourceStatusPayload (..),

  -- * Pure event builders (exported for contract tests)
  buildInsightCollectedEvent,
  buildInsightCollectFailedEvent,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson (ToJSON (..), object, (.=))
import Data.Text (Text)
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Data.ULID qualified as ULID
import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (
  InsightArtifact (..),
  SourceCollectionStatus (..),
  SourceOutcome (..),
  SourceType (..),
 )
import Domain.InsightCollection.ReasonCode (ReasonCode)
import Infrastructure.Wire.ReasonCodeWire (reasonCodeToWire)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubPublisher, TopicName, publishCloudEvent)
import UseCase.CollectInsights (InsightCollectionEventPublisher (..))

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

-- | Must-INFRA-022: Environment for Pub/Sub insight event publishing.
data PubSubInsightEventPublisherEnv = PubSubInsightEventPublisherEnv
  { publisher :: PubSubPublisher
  , collectedTopicName :: TopicName
  , failedTopicName :: TopicName
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype PubSubInsightEventPublisherT m a = PubSubInsightEventPublisherT
  { unPubSubInsightEventPublisherT :: ReaderT PubSubInsightEventPublisherEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runPubSubInsightEventPublisherT ::
  PubSubInsightEventPublisherEnv ->
  PubSubInsightEventPublisherT m a ->
  m a
runPubSubInsightEventPublisherT environment action =
  runReaderT (unPubSubInsightEventPublisherT action) environment

-- ---------------------------------------------------------------------------
-- Payload types
-- ---------------------------------------------------------------------------

-- | Payload for insight.collected event.
data SourceStatusPayload = SourceStatusPayload
  { sourceType :: Text
  , outcome :: Text
  }
  deriving stock (Eq, Show)

instance ToJSON SourceStatusPayload where
  toJSON statusPayload =
    object
      [ "sourceType" .= statusPayload.sourceType
      , "outcome" .= statusPayload.outcome
      ]

-- | Payload for insight.collected CloudEvent.
data InsightCollectedPayload = InsightCollectedPayload
  { count :: Int
  , storagePath :: Text
  , sourceStatus :: [SourceStatusPayload]
  }
  deriving stock (Eq, Show)

instance ToJSON InsightCollectedPayload where
  toJSON payloadValue =
    object
      [ "count" .= payloadValue.count
      , "storagePath" .= payloadValue.storagePath
      , "sourceStatus" .= payloadValue.sourceStatus
      ]

-- | Payload for insight.collect.failed CloudEvent.
data InsightCollectFailedPayload = InsightCollectFailedPayload
  { reasonCode :: Text
  , detail :: Maybe Text
  }
  deriving stock (Eq, Show)

instance ToJSON InsightCollectFailedPayload where
  toJSON payloadValue =
    object $
      ["reasonCode" .= payloadValue.reasonCode]
        <> maybe [] (\detailText -> ["detail" .= detailText]) payloadValue.detail

-- ---------------------------------------------------------------------------
-- InsightCollectionEventPublisher instance
-- ---------------------------------------------------------------------------

instance InsightCollectionEventPublisher (PubSubInsightEventPublisherT IO) where
  -- Must-INFRA-020
  publishInsightCollected _collectionIdentifier artifact traceValue =
    PubSubInsightEventPublisherT $ do
      environment <- ask
      liftIO $ do
        now <- getCurrentTime
        newEventIdentifier <- ULID.getULID
        let event = buildInsightCollectedEvent newEventIdentifier now traceValue.value artifact
        _ <- publishCloudEvent environment.publisher environment.collectedTopicName event
        pure ()

  -- Must-INFRA-021
  publishInsightCollectFailed _collectionIdentifier reasonCode maybeDetail traceValue =
    PubSubInsightEventPublisherT $ do
      environment <- ask
      liftIO $ do
        now <- getCurrentTime
        newEventIdentifier <- ULID.getULID
        let event = buildInsightCollectFailedEvent newEventIdentifier now traceValue.value reasonCode maybeDetail
        _ <- publishCloudEvent environment.publisher environment.failedTopicName event
        pure ()

-- ---------------------------------------------------------------------------
-- Pure event builders (exported for contract tests)
-- ---------------------------------------------------------------------------

-- | Build an 'insight.collected' CloudEvent from pure inputs.
buildInsightCollectedEvent ::
  ULID ->
  UTCTime ->
  ULID ->
  InsightArtifact ->
  CloudEvent InsightCollectedPayload
buildInsightCollectedEvent newEventIdentifier now traceUlid artifact =
  let statusPayloads = map sourceCollectionStatusToPayload artifact.sourceStatus
      payloadValue =
        InsightCollectedPayload
          { count = artifact.count
          , storagePath = artifact.storagePath
          , sourceStatus = statusPayloads
          }
   in CloudEvent
        { identifier = newEventIdentifier
        , eventType = "insight.collected"
        , occurredAt = now
        , trace = traceUlid
        , schemaVersion = "1.0.0"
        , payload = payloadValue
        }

-- | Build an 'insight.collect.failed' CloudEvent from pure inputs.
buildInsightCollectFailedEvent ::
  ULID ->
  UTCTime ->
  ULID ->
  ReasonCode ->
  Maybe Text ->
  CloudEvent InsightCollectFailedPayload
buildInsightCollectFailedEvent newEventIdentifier now traceUlid reasonCode maybeDetail =
  let payloadValue =
        InsightCollectFailedPayload
          { reasonCode = reasonCodeToWire reasonCode
          , detail = maybeDetail
          }
   in CloudEvent
        { identifier = newEventIdentifier
        , eventType = "insight.collect.failed"
        , occurredAt = now
        , trace = traceUlid
        , schemaVersion = "1.0.0"
        , payload = payloadValue
        }

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

sourceTypeToText :: SourceType -> Text
sourceTypeToText X = "x"
sourceTypeToText YouTube = "youtube"
sourceTypeToText Paper = "paper"
sourceTypeToText GitHub = "github"

sourceOutcomeToText :: SourceOutcome -> Text
sourceOutcomeToText SourceSuccess = "success"
sourceOutcomeToText SourceFailed = "failed"
sourceOutcomeToText QuotaExhausted = "quota_exhausted"

sourceCollectionStatusToPayload :: SourceCollectionStatus -> SourceStatusPayload
sourceCollectionStatusToPayload sourceCollectionStatus =
  SourceStatusPayload
    { sourceType = sourceTypeToText sourceCollectionStatus.sourceType
    , outcome = sourceOutcomeToText sourceCollectionStatus.status
    }
