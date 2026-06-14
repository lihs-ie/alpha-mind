module Infrastructure.Publisher.PubSubCommandsPublisher (
  PubSubCommandsPublisherEnv (..),
  MarketCollectRequestedPayload (..),
  InsightCollectRequestedPayload (..),
  InsightCollectOptions (..),
  publishMarketCollectRequested,
  publishInsightCollectRequested,
) where

import Data.Aeson (ToJSON (..), object, (.=))
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubPublisher, TopicName, publishCloudEvent)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

data PubSubCommandsPublisherEnv = PubSubCommandsPublisherEnv
  { publisher :: PubSubPublisher
  , marketCollectTopicName :: TopicName
  , insightCollectTopicName :: TopicName
  }

-- ---------------------------------------------------------------------------
-- Payloads
-- ---------------------------------------------------------------------------

-- | Payload for the @market.collect.requested@ event.
data MarketCollectRequestedPayload = MarketCollectRequestedPayload
  { targetDate :: Text
  -- ^ ISO-8601 date (YYYY-MM-DD).
  , requestedBy :: Text
  -- ^ \"user\" for manual commands.
  }

instance ToJSON MarketCollectRequestedPayload where
  toJSON payloadValue =
    object
      [ "targetDate" .= payloadValue.targetDate
      , "requestedBy" .= payloadValue.requestedBy
      ]

-- | Options for the @insight.collect.requested@ event.
data InsightCollectOptions = InsightCollectOptions
  { forceRecollect :: Bool
  , dryRun :: Bool
  , maxItemsPerSource :: Maybe Int
  }

instance ToJSON InsightCollectOptions where
  toJSON optionsValue =
    object
      [ "forceRecollect" .= optionsValue.forceRecollect
      , "dryRun" .= optionsValue.dryRun
      , "maxItemsPerSource" .= optionsValue.maxItemsPerSource
      ]

-- | Payload for the @insight.collect.requested@ event.
data InsightCollectRequestedPayload = InsightCollectRequestedPayload
  { targetDate :: Text
  -- ^ ISO-8601 date (YYYY-MM-DD).
  , requestedBy :: Text
  -- ^ \"user\" for manual commands.
  , sourceTypes :: Maybe [Text]
  -- ^ Optional source type filter.
  , options :: Maybe InsightCollectOptions
  -- ^ Optional collection options.
  }

instance ToJSON InsightCollectRequestedPayload where
  toJSON payloadValue =
    object
      [ "targetDate" .= payloadValue.targetDate
      , "requestedBy" .= payloadValue.requestedBy
      , "sourceTypes" .= payloadValue.sourceTypes
      , "options" .= payloadValue.options
      ]

-- ---------------------------------------------------------------------------
-- Publishers
-- ---------------------------------------------------------------------------

-- | Publish a @market.collect.requested@ CloudEvent to Pub/Sub.
publishMarketCollectRequested ::
  PubSubCommandsPublisherEnv ->
  -- | Event identifier (ULID, for idempotency).
  ULID ->
  -- | Trace ULID.
  ULID ->
  -- | Event timestamp.
  UTCTime ->
  -- | ISO-8601 target date string.
  Text ->
  IO ()
publishMarketCollectRequested publisherEnv eventIdentifier traceValue occurredAtValue targetDateValue = do
  let event =
        CloudEvent
          { identifier = eventIdentifier
          , eventType = "market.collect.requested"
          , occurredAt = occurredAtValue
          , trace = traceValue
          , schemaVersion = "1.0.0"
          , payload =
              MarketCollectRequestedPayload
                { targetDate = targetDateValue
                , requestedBy = "user"
                }
          }
  _ <- publishCloudEvent publisherEnv.publisher publisherEnv.marketCollectTopicName event
  pure ()

-- | Publish an @insight.collect.requested@ CloudEvent to Pub/Sub.
publishInsightCollectRequested ::
  PubSubCommandsPublisherEnv ->
  -- | Event identifier (ULID, for idempotency).
  ULID ->
  -- | Trace ULID.
  ULID ->
  -- | Event timestamp.
  UTCTime ->
  -- | ISO-8601 target date string.
  Text ->
  -- | Optional source type filter.
  Maybe [Text] ->
  -- | Optional collection options.
  Maybe InsightCollectOptions ->
  IO ()
publishInsightCollectRequested publisherEnv eventIdentifier traceValue occurredAtValue targetDateValue sourceTypesValue optionsValue = do
  let event =
        CloudEvent
          { identifier = eventIdentifier
          , eventType = "insight.collect.requested"
          , occurredAt = occurredAtValue
          , trace = traceValue
          , schemaVersion = "1.1.0"
          , payload =
              InsightCollectRequestedPayload
                { targetDate = targetDateValue
                , requestedBy = "user"
                , sourceTypes = sourceTypesValue
                , options = optionsValue
                }
          }
  _ <- publishCloudEvent publisherEnv.publisher publisherEnv.insightCollectTopicName event
  pure ()
