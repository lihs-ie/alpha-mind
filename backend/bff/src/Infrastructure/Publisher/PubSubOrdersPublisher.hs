{- | Pub/Sub publisher for order action events.

Publishes the following CloudEvents as defined in @asyncapi.yaml@:

  * @orders.approved@  — emitted after a successful approve action
  * @orders.rejected@  — emitted after a successful reject action
  * @orders.proposed@  — emitted after a successful retry action (re-proposes)
-}
module Infrastructure.Publisher.PubSubOrdersPublisher (
  PubSubOrdersPublisherEnv (..),
  OrdersDecisionPayload (..),
  OrdersProposedPayload (..),
  publishOrdersApproved,
  publishOrdersRejected,
  publishOrdersProposed,
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

data PubSubOrdersPublisherEnv = PubSubOrdersPublisherEnv
  { publisher :: PubSubPublisher
  , ordersApprovedTopicName :: TopicName
  , ordersRejectedTopicName :: TopicName
  , ordersProposedTopicName :: TopicName
  }

-- ---------------------------------------------------------------------------
-- Payloads
-- ---------------------------------------------------------------------------

-- | Payload for @orders.approved@ and @orders.rejected@ events.
data OrdersDecisionPayload = OrdersDecisionPayload
  { identifier :: Text
  -- ^ Order identifier (ULID).
  , decision :: Text
  -- ^ Either @"approved"@ or @"rejected"@.
  , reasonCode :: Maybe Text
  -- ^ Required when decision is @"rejected"@.
  , actionReasonCode :: Maybe Text
  -- ^ Operator-provided reason code.
  }

instance ToJSON OrdersDecisionPayload where
  toJSON decisionPayload =
    object
      [ "identifier" .= decisionPayload.identifier
      , "decision" .= decisionPayload.decision
      , "reasonCode" .= decisionPayload.reasonCode
      , "actionReasonCode" .= decisionPayload.actionReasonCode
      ]

-- | Payload for @orders.proposed@ (retry) event.
newtype OrdersProposedPayload = OrdersProposedPayload
  { identifier :: Text
  -- ^ Order identifier (ULID).
  }

instance ToJSON OrdersProposedPayload where
  toJSON proposedPayload =
    object
      [ "identifier" .= proposedPayload.identifier
      ]

-- ---------------------------------------------------------------------------
-- Publishers
-- ---------------------------------------------------------------------------

-- | Publish an @orders.approved@ CloudEvent to Pub/Sub.
publishOrdersApproved ::
  PubSubOrdersPublisherEnv ->
  ULID ->
  ULID ->
  UTCTime ->
  Text ->
  Maybe Text ->
  IO ()
publishOrdersApproved publisherEnv eventIdentifier traceValue occurredAtValue orderIdentifier maybeActionReasonCode = do
  let event =
        CloudEvent
          { identifier = eventIdentifier
          , eventType = "orders.approved"
          , occurredAt = occurredAtValue
          , trace = traceValue
          , schemaVersion = "1.0"
          , payload =
              OrdersDecisionPayload
                { identifier = orderIdentifier
                , decision = "approved"
                , reasonCode = Nothing
                , actionReasonCode = maybeActionReasonCode
                }
          }
  _ <- publishCloudEvent publisherEnv.publisher publisherEnv.ordersApprovedTopicName event
  pure ()

-- | Publish an @orders.rejected@ CloudEvent to Pub/Sub.
publishOrdersRejected ::
  PubSubOrdersPublisherEnv ->
  ULID ->
  ULID ->
  UTCTime ->
  Text ->
  Maybe Text ->
  IO ()
publishOrdersRejected publisherEnv eventIdentifier traceValue occurredAtValue orderIdentifier maybeActionReasonCode = do
  let event =
        CloudEvent
          { identifier = eventIdentifier
          , eventType = "orders.rejected"
          , occurredAt = occurredAtValue
          , trace = traceValue
          , schemaVersion = "1.0"
          , payload =
              OrdersDecisionPayload
                { identifier = orderIdentifier
                , decision = "rejected"
                , reasonCode = Just "MANUAL_REJECTION"
                , actionReasonCode = maybeActionReasonCode
                }
          }
  _ <- publishCloudEvent publisherEnv.publisher publisherEnv.ordersRejectedTopicName event
  pure ()

-- | Publish an @orders.proposed@ CloudEvent to Pub/Sub (retry re-proposes the order).
publishOrdersProposed ::
  PubSubOrdersPublisherEnv ->
  ULID ->
  ULID ->
  UTCTime ->
  Text ->
  IO ()
publishOrdersProposed publisherEnv eventIdentifier traceValue occurredAtValue orderIdentifier = do
  let event =
        CloudEvent
          { identifier = eventIdentifier
          , eventType = "orders.proposed"
          , occurredAt = occurredAtValue
          , trace = traceValue
          , schemaVersion = "1.0"
          , payload = OrdersProposedPayload{identifier = orderIdentifier}
          }
  _ <- publishCloudEvent publisherEnv.publisher publisherEnv.ordersProposedTopicName event
  pure ()
