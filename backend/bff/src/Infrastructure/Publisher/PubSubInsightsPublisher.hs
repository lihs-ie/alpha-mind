{- | Pub/Sub publisher for insight action events.

Publishes the following CloudEvent as defined in @asyncapi.yaml@:

  * @hypothesis.proposed@ — emitted after a successful hypothesize action
    on an insight record (channel address: @hypothesis.proposed@)
-}
module Infrastructure.Publisher.PubSubInsightsPublisher (
  PubSubInsightsPublisherEnv (..),
  HypothesisProposedPayload (..),
  publishHypothesisProposed,
)
where

import Data.Aeson (ToJSON (..), object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubPublisher, TopicName, publishCloudEvent)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

data PubSubInsightsPublisherEnv = PubSubInsightsPublisherEnv
  { publisher :: PubSubPublisher
  , hypothesisProposedTopicName :: TopicName
  }

-- ---------------------------------------------------------------------------
-- Payloads
-- ---------------------------------------------------------------------------

{- | Payload for the @hypothesis.proposed@ event.

Follows the @HypothesisProposedPayload@ schema from @asyncapi.yaml@.
All fields derived from the source insight record; title is synthesised
from the insight summary.
-}
data HypothesisProposedPayload = HypothesisProposedPayload
  { identifier :: Text
  -- ^ New hypothesis ULID (generated at request time).
  , sourceInsight :: Text
  -- ^ Insight identifier that triggered the hypothesis.
  , skillVersion :: Maybe Text
  -- ^ Skill version from the source insight.
  }

instance ToJSON HypothesisProposedPayload where
  toJSON proposedPayload =
    object
      [ "identifier" .= proposedPayload.identifier
      , "sourceInsight" .= proposedPayload.sourceInsight
      , "skillVersion" .= proposedPayload.skillVersion
      ]

-- ---------------------------------------------------------------------------
-- Publisher
-- ---------------------------------------------------------------------------

-- | Publish a @hypothesis.proposed@ CloudEvent to Pub/Sub.
publishHypothesisProposed ::
  PubSubInsightsPublisherEnv ->
  -- | Event identifier (ULID).
  ULID ->
  -- | Trace identifier (ULID).
  ULID ->
  -- | New hypothesis identifier (ULID).
  ULID ->
  -- | Event timestamp.
  UTCTime ->
  -- | Source insight identifier.
  Text ->
  -- | Skill version from the source insight.
  Maybe Text ->
  IO ()
publishHypothesisProposed publisherEnvironment eventIdentifier traceValue hypothesisIdentifier occurredAtValue insightIdentifier maybeSkillVersion = do
  let event =
        CloudEvent
          { identifier = eventIdentifier
          , eventType = "hypothesis.proposed"
          , occurredAt = occurredAtValue
          , trace = traceValue
          , schemaVersion = "1.0"
          , payload =
              HypothesisProposedPayload
                { identifier = Text.pack (show hypothesisIdentifier)
                , sourceInsight = insightIdentifier
                , skillVersion = maybeSkillVersion
                }
          }
  _ <- publishCloudEvent publisherEnvironment.publisher publisherEnvironment.hypothesisProposedTopicName event
  pure ()
