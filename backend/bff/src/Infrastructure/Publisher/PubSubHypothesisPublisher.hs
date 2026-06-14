{- | Pub/Sub publisher for hypothesis action events.

Publishes the following CloudEvents as defined in @asyncapi.yaml@:

  * @hypothesis.promoted@         — emitted after a successful promote action
  * @hypothesis.rejected@         — emitted after a successful reject action
  * @hypothesis.retest.requested@ — emitted after a successful retest request
-}
module Infrastructure.Publisher.PubSubHypothesisPublisher (
  PubSubHypothesisPublisherEnv (..),
  HypothesisDecisionPayload (..),
  HypothesisRetestRequestedPayload (..),
  publishHypothesisPromoted,
  publishHypothesisRejected,
  publishHypothesisRetestRequested,
)
where

import Data.Aeson (ToJSON (..), object, (.=))
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubPublisher, TopicName, publishCloudEvent)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

data PubSubHypothesisPublisherEnv = PubSubHypothesisPublisherEnv
  { publisher :: PubSubPublisher
  , hypothesisPromotedTopicName :: TopicName
  , hypothesisRejectedTopicName :: TopicName
  , hypothesisRetestRequestedTopicName :: TopicName
  }

-- ---------------------------------------------------------------------------
-- Payloads
-- ---------------------------------------------------------------------------

{- | Payload for @hypothesis.promoted@ and @hypothesis.rejected@ events.

Follows the @HypothesisDecisionPayload@ schema from @asyncapi.yaml@.
-}
data HypothesisDecisionPayload = HypothesisDecisionPayload
  { identifier :: Text
  -- ^ Hypothesis identifier (ULID).
  , decision :: Text
  -- ^ Either @"promoted"@ or @"rejected"@.
  , actionReasonCode :: Text
  -- ^ Operator-provided reason code.
  , promotionMode :: Text
  -- ^ Either @"manual"@ or @"auto"@.
  , mnpiSelfDeclared :: Bool
  -- ^ Whether MNPI self-declaration was recorded.
  , insiderRisk :: Text
  -- ^ Insider risk level (@"low"@, @"medium"@, or @"high"@).
  }

instance ToJSON HypothesisDecisionPayload where
  toJSON decisionPayload =
    object
      [ "identifier" .= decisionPayload.identifier
      , "decision" .= decisionPayload.decision
      , "actionReasonCode" .= decisionPayload.actionReasonCode
      , "promotionMode" .= decisionPayload.promotionMode
      , "mnpiSelfDeclared" .= decisionPayload.mnpiSelfDeclared
      , "insiderRisk" .= decisionPayload.insiderRisk
      ]

{- | Payload for @hypothesis.retest.requested@ event.

Follows the @HypothesisRetestRequestedPayload@ schema from @asyncapi.yaml@.
-}
newtype HypothesisRetestRequestedPayload = HypothesisRetestRequestedPayload
  { identifier :: Text
  -- ^ Hypothesis identifier (ULID).
  }

instance ToJSON HypothesisRetestRequestedPayload where
  toJSON retestPayload =
    object
      [ "identifier" .= retestPayload.identifier
      ]

-- ---------------------------------------------------------------------------
-- Publishers
-- ---------------------------------------------------------------------------

-- | Publish a @hypothesis.promoted@ CloudEvent to Pub/Sub.
publishHypothesisPromoted ::
  PubSubHypothesisPublisherEnv ->
  -- | Event identifier (ULID).
  ULID ->
  -- | Trace identifier (ULID).
  ULID ->
  -- | Event timestamp.
  UTCTime ->
  -- | Hypothesis identifier.
  Text ->
  -- | Operator action reason code.
  Text ->
  -- | Promotion mode (@"manual"@ or @"auto"@).
  Text ->
  -- | Whether MNPI was self-declared.
  Bool ->
  -- | Insider risk level.
  Text ->
  IO ()
publishHypothesisPromoted publisherEnvironment eventIdentifier traceValue occurredAtValue hypothesisIdentifier actionReasonCodeValue promotionModeValue mnpiSelfDeclaredValue insiderRiskValue = do
  let event =
        CloudEvent
          { identifier = eventIdentifier
          , eventType = "hypothesis.promoted"
          , occurredAt = occurredAtValue
          , trace = traceValue
          , schemaVersion = "1.0"
          , payload =
              HypothesisDecisionPayload
                { identifier = hypothesisIdentifier
                , decision = "promoted"
                , actionReasonCode = actionReasonCodeValue
                , promotionMode = promotionModeValue
                , mnpiSelfDeclared = mnpiSelfDeclaredValue
                , insiderRisk = insiderRiskValue
                }
          }
  _ <- publishCloudEvent publisherEnvironment.publisher publisherEnvironment.hypothesisPromotedTopicName event
  pure ()

-- | Publish a @hypothesis.rejected@ CloudEvent to Pub/Sub.
publishHypothesisRejected ::
  PubSubHypothesisPublisherEnv ->
  -- | Event identifier (ULID).
  ULID ->
  -- | Trace identifier (ULID).
  ULID ->
  -- | Event timestamp.
  UTCTime ->
  -- | Hypothesis identifier.
  Text ->
  -- | Operator action reason code.
  Text ->
  -- | Whether MNPI was self-declared.
  Bool ->
  -- | Insider risk level.
  Text ->
  IO ()
publishHypothesisRejected publisherEnvironment eventIdentifier traceValue occurredAtValue hypothesisIdentifier actionReasonCodeValue mnpiSelfDeclaredValue insiderRiskValue = do
  let event =
        CloudEvent
          { identifier = eventIdentifier
          , eventType = "hypothesis.rejected"
          , occurredAt = occurredAtValue
          , trace = traceValue
          , schemaVersion = "1.0"
          , payload =
              HypothesisDecisionPayload
                { identifier = hypothesisIdentifier
                , decision = "rejected"
                , actionReasonCode = actionReasonCodeValue
                , promotionMode = "manual"
                , mnpiSelfDeclared = mnpiSelfDeclaredValue
                , insiderRisk = insiderRiskValue
                }
          }
  _ <- publishCloudEvent publisherEnvironment.publisher publisherEnvironment.hypothesisRejectedTopicName event
  pure ()

-- | Publish a @hypothesis.retest.requested@ CloudEvent to Pub/Sub.
publishHypothesisRetestRequested ::
  PubSubHypothesisPublisherEnv ->
  -- | Event identifier (ULID).
  ULID ->
  -- | Trace identifier (ULID).
  ULID ->
  -- | Event timestamp.
  UTCTime ->
  -- | Hypothesis identifier.
  Text ->
  IO ()
publishHypothesisRetestRequested publisherEnvironment eventIdentifier traceValue occurredAtValue hypothesisIdentifier = do
  let event =
        CloudEvent
          { identifier = eventIdentifier
          , eventType = "hypothesis.retest.requested"
          , occurredAt = occurredAtValue
          , trace = traceValue
          , schemaVersion = "1.0"
          , payload = HypothesisRetestRequestedPayload{identifier = hypothesisIdentifier}
          }
  _ <- publishCloudEvent publisherEnvironment.publisher publisherEnvironment.hypothesisRetestRequestedTopicName event
  pure ()
