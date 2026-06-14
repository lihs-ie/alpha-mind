module Infrastructure.Publisher.PubSubOperationsPublisher (
  PubSubOperationsPublisherEnv (..),
  KillSwitchChangedPayload (..),
  publishKillSwitchChanged,
) where

import Data.Aeson (ToJSON (..), object, (.=))
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubPublisher, TopicName, publishCloudEvent)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

data PubSubOperationsPublisherEnv = PubSubOperationsPublisherEnv
  { publisher :: PubSubPublisher
  , killSwitchTopicName :: TopicName
  }

-- ---------------------------------------------------------------------------
-- Payload
-- ---------------------------------------------------------------------------

newtype KillSwitchChangedPayload = KillSwitchChangedPayload
  { enabled :: Bool
  }

instance ToJSON KillSwitchChangedPayload where
  toJSON killSwitchPayload =
    object
      [ "enabled" .= killSwitchPayload.enabled
      ]

-- ---------------------------------------------------------------------------
-- Publisher
-- ---------------------------------------------------------------------------

-- | Publish a @operation.kill_switch.changed@ CloudEvent to Pub/Sub.
publishKillSwitchChanged ::
  PubSubOperationsPublisherEnv ->
  -- | Event identifier (ULID, for idempotency).
  ULID ->
  -- | Trace ULID.
  ULID ->
  -- | Event timestamp.
  UTCTime ->
  -- | New kill switch enabled value.
  Bool ->
  IO ()
publishKillSwitchChanged publisherEnv eventIdentifier traceValue occurredAtValue enabledValue = do
  let event =
        CloudEvent
          { identifier = eventIdentifier
          , eventType = "operation.kill_switch.changed"
          , occurredAt = occurredAtValue
          , trace = traceValue
          , schemaVersion = "1.0"
          , payload = KillSwitchChangedPayload{enabled = enabledValue}
          }
  _ <- publishCloudEvent publisherEnv.publisher publisherEnv.killSwitchTopicName event
  pure ()
