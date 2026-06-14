{-# OPTIONS_GHC -fno-warn-orphans #-}

{- | Pub/Sub push endpoint handler for the agent-orchestrator service.

 Implements @POST /pubsub/events@.

 Decode chain (Must-11):
   1. Raw HTTP body → 'decodePubSubPush' → 'CloudEvent Value'
   2. 'CloudEvent.eventType' == @"insight.collected"@ → decode payload as 'InsightCollectedEvent'
   3. 'CloudEvent.eventType' == @"hypothesis.retest.requested"@ → decode payload as 'RetestRequestedEvent'
   4. Unknown event type → 'PubSubPushUnknownEventType' (HTTP 200 ack)
   5. Payload JSON parse failure → 'PubSubPushSchemaInvalid' (HTTP 200 ack)
   6. Call corresponding usecase function on success.

 HTTP status mapping (Must-13):
   * 'PubSubPushOrchestrationSucceeded' → 200
   * 'PubSubPushOrchestrationDuplicate' → 200
   * 'PubSubPushSchemaInvalid'          → 200 (permanent; do not re-deliver)
   * 'PubSubPushUnknownEventType'       → 200 (ack; ignore)
   * 'PubSubPushOrchestrationFailed'    → 500 (transient; re-deliver)
-}
module Presentation.PubSubHandler (
  -- * Core logic (IO, usable in unit tests)
  processPubSubPush,

  -- * Seam (injectable usecase runner for unit tests)
  processPubSubPushWith,

  -- * Servant handler
  handlePubSubPush,

  -- * Result type
  PubSubPushResult (..),

  -- * HTTP status mapping
  pubSubPushResultToStatus,
) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (FromJSON (..), Value, withObject, (.:))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Data.ULID qualified as ULID
import Domain.HypothesisOrchestration (Trace (..))
import Domain.HypothesisOrchestration.Aggregate (
  HypothesisProposalIdentifier (..),
 )
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.FailureKnowledge (
  FailureKnowledgeIdentifier (..),
 )
import Domain.HypothesisOrchestration.HypothesisProposalFactory (
  InsightCollectedEvent (..),
  RetestRequestedEvent (..),
 )
import Domain.HypothesisOrchestration.NonRetryableReasonSpecification (
  NonRetryableReasonSpecification (..),
  isSatisfiedBy,
 )
import Domain.HypothesisOrchestration.OrchestrationDispatch (
  OrchestrationDispatchIdentifier (..),
 )
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (decodePubSubPush)
import Observability.Logging (LogContext (..), LogEnv, logErrorWith, logInfoWith)
import Presentation.AppM (AppEnv (..), runAppM)
import Servant (Handler, ServerError (..), err500, throwError)
import Text.Read (readMaybe)
import UseCase.HypothesisOrchestration.HypothesisOrchestrationService (
  orchestrateFromInsight,
  orchestrateFromRetest,
 )

-- ---------------------------------------------------------------------------
-- Result type (Must-13)
-- ---------------------------------------------------------------------------

{- | Must-13: Result of processing a Pub/Sub push message.

 HTTP status mapping:
   * 'PubSubPushOrchestrationSucceeded'   → 200
   * 'PubSubPushOrchestrationDuplicate'   → 200 (idempotent)
   * 'PubSubPushSchemaInvalid Text'       → 200 (permanent decode error)
   * 'PubSubPushUnknownEventType Text'    → 200 (unrecognised event; ack)
   * 'PubSubPushOrchestrationFailed Text' → 500 (transient error; re-deliver)
-}
data PubSubPushResult
  = PubSubPushOrchestrationSucceeded
  | PubSubPushOrchestrationDuplicate
  | PubSubPushSchemaInvalid Text
  | PubSubPushUnknownEventType Text
  | PubSubPushOrchestrationFailed Text
  deriving stock (Eq, Show)

-- | Maps 'PubSubPushResult' to the HTTP status policy (Must-13).
pubSubPushResultToStatus :: PubSubPushResult -> Either ServerError PubSubPushResult
pubSubPushResultToStatus PubSubPushOrchestrationSucceeded = Right PubSubPushOrchestrationSucceeded
pubSubPushResultToStatus PubSubPushOrchestrationDuplicate = Right PubSubPushOrchestrationDuplicate
pubSubPushResultToStatus (PubSubPushSchemaInvalid message) = Right (PubSubPushSchemaInvalid message)
pubSubPushResultToStatus (PubSubPushUnknownEventType message) = Right (PubSubPushUnknownEventType message)
pubSubPushResultToStatus (PubSubPushOrchestrationFailed message) =
  Left err500{errBody = "orchestration_failed: " <> encodeUtf8Lazy message}

-- ---------------------------------------------------------------------------
-- CloudEventPayload intermediate type (OQ-01)
-- ---------------------------------------------------------------------------

{- | OQ-01: Intermediate type wrapping the decoded usecase input.

 Allows 'processPubSubPushWith' to have a single injectable seam signature
 that works for both 'insight.collected' and 'hypothesis.retest.requested'.
-}
data CloudEventPayload
  = InsightPayload InsightCollectedEvent
  | RetestPayload RetestRequestedEvent

-- ---------------------------------------------------------------------------
-- Core logic (IO — testable without Servant)
-- ---------------------------------------------------------------------------

{- | Must-10: Process a Pub/Sub push body with an injectable usecase runner.

 The usecase runner argument allows tests to substitute a fake implementation
 without any test code entering src/. The production wrapper 'processPubSubPush'
 passes the real 'runAppM'-based runner.

 Must-12: ULID identifiers for 'OrchestrationDispatchIdentifier',
 'HypothesisProposalIdentifier', and 'FailureKnowledgeIdentifier' are
 generated via 'Data.ULID.getULID'.
-}
processPubSubPushWith ::
  LogEnv ->
  ( UTCTime ->
    OrchestrationDispatchIdentifier ->
    HypothesisProposalIdentifier ->
    FailureKnowledgeIdentifier ->
    CloudEventPayload ->
    IO (Either DomainError ())
  ) ->
  ByteString ->
  IO PubSubPushResult
processPubSubPushWith logEnvironment runUseCase body =
  case decodePubSubPush @Value body of
    Left pubSubError -> do
      let errorMessage = Text.pack (show pubSubError)
      logSchemaDecodeError logEnvironment errorMessage Nothing Nothing
      pure (PubSubPushSchemaInvalid errorMessage)
    Right cloudEvent -> do
      let traceText = Just (Text.pack (show cloudEvent.trace))
          identifierText = Just (Text.pack (show cloudEvent.identifier))
          eventTypeText = cloudEvent.eventType
      logReceived logEnvironment traceText identifierText eventTypeText
      pushResult <- dispatchCloudEvent logEnvironment runUseCase cloudEvent
      logResult logEnvironment traceText identifierText eventTypeText pushResult
      pure pushResult

{- | Dispatch a decoded 'CloudEvent' to the appropriate usecase runner.

 Must-11: Routes on 'eventType' string:
   * @"insight.collected"@           → parse payload as 'InsightCollectedEvent'
   * @"hypothesis.retest.requested"@ → parse payload as 'RetestRequestedEvent'
   * other                           → 'PubSubPushUnknownEventType'
-}
dispatchCloudEvent ::
  LogEnv ->
  ( UTCTime ->
    OrchestrationDispatchIdentifier ->
    HypothesisProposalIdentifier ->
    FailureKnowledgeIdentifier ->
    CloudEventPayload ->
    IO (Either DomainError ())
  ) ->
  CloudEvent Value ->
  IO PubSubPushResult
dispatchCloudEvent logEnvironment runUseCase cloudEvent =
  case cloudEvent.eventType of
    "insight.collected" ->
      case parseInsightPayload cloudEvent of
        Left parseError -> do
          logSchemaDecodeError
            logEnvironment
            parseError
            (Just (Text.pack (show cloudEvent.trace)))
            (Just (Text.pack (show cloudEvent.identifier)))
          pure (PubSubPushSchemaInvalid parseError)
        Right insightEvent -> do
          currentTime <- getCurrentTime
          dispatchIdentifier <- OrchestrationDispatchIdentifier <$> ULID.getULID
          proposalIdentifier <- HypothesisProposalIdentifier <$> ULID.getULID
          failureKnowledgeIdentifier <- FailureKnowledgeIdentifier <$> ULID.getULID
          result <-
            runUseCase
              currentTime
              dispatchIdentifier
              proposalIdentifier
              failureKnowledgeIdentifier
              (InsightPayload insightEvent)
          pure (domainResultToPushResult result)
    "hypothesis.retest.requested" ->
      case parseRetestPayload cloudEvent of
        Left parseError -> do
          logSchemaDecodeError
            logEnvironment
            parseError
            (Just (Text.pack (show cloudEvent.trace)))
            (Just (Text.pack (show cloudEvent.identifier)))
          pure (PubSubPushSchemaInvalid parseError)
        Right retestEvent -> do
          currentTime <- getCurrentTime
          dispatchIdentifier <- OrchestrationDispatchIdentifier <$> ULID.getULID
          proposalIdentifier <- HypothesisProposalIdentifier <$> ULID.getULID
          failureKnowledgeIdentifier <- FailureKnowledgeIdentifier <$> ULID.getULID
          result <-
            runUseCase
              currentTime
              dispatchIdentifier
              proposalIdentifier
              failureKnowledgeIdentifier
              (RetestPayload retestEvent)
          pure (domainResultToPushResult result)
    unknownType ->
      pure (PubSubPushUnknownEventType unknownType)

{- | Process a Pub/Sub push body, returning a 'PubSubPushResult'.

 Delegates to 'processPubSubPushWith' with the real 'runAppM'-based runner.
-}
processPubSubPush ::
  AppEnv ->
  ByteString ->
  IO PubSubPushResult
processPubSubPush appEnv body =
  processPubSubPushWith
    appEnv.logEnv
    ( \currentTime dispatchIdentifier proposalIdentifier failureKnowledgeIdentifier cloudEventPayload ->
        case cloudEventPayload of
          InsightPayload insightEvent ->
            runAppM appEnv $
              orchestrateFromInsight
                dispatchIdentifier
                proposalIdentifier
                failureKnowledgeIdentifier
                insightEvent
                currentTime
          RetestPayload retestEvent ->
            runAppM appEnv $
              orchestrateFromRetest
                dispatchIdentifier
                proposalIdentifier
                failureKnowledgeIdentifier
                retestEvent
                currentTime
    )
    body

-- ---------------------------------------------------------------------------
-- Servant handler (delegates to processPubSubPush)
-- ---------------------------------------------------------------------------

{- | Servant 'Handler' wrapper around 'processPubSubPush'.

 Translates 'PubSubPushResult' to the appropriate HTTP status via
 'pubSubPushResultToStatus'.
-}
handlePubSubPush ::
  AppEnv ->
  ByteString ->
  Handler PubSubPushResult
handlePubSubPush appEnv body = do
  pushResult <- liftIO (processPubSubPush appEnv body)
  case pubSubPushResultToStatus pushResult of
    Left serverError -> throwError serverError
    Right successResult -> pure successResult

-- ---------------------------------------------------------------------------
-- Payload parsers
-- ---------------------------------------------------------------------------

-- | Parse the CloudEvent payload as 'InsightCollectedEvent'.
parseInsightPayload :: CloudEvent Value -> Either Text InsightCollectedEvent
parseInsightPayload cloudEvent =
  case Aeson.fromJSON cloudEvent.payload of
    Aeson.Error message -> Left (Text.pack message)
    Aeson.Success event -> Right event

-- | Parse the CloudEvent payload as 'RetestRequestedEvent'.
parseRetestPayload :: CloudEvent Value -> Either Text RetestRequestedEvent
parseRetestPayload cloudEvent =
  case Aeson.fromJSON cloudEvent.payload of
    Aeson.Error message -> Left (Text.pack message)
    Aeson.Success event -> Right event

-- ---------------------------------------------------------------------------
-- FromJSON instances for factory input types
-- ---------------------------------------------------------------------------

instance FromJSON InsightCollectedEvent where
  parseJSON = withObject "InsightCollectedEvent" $ \object -> do
    insightIdentifierText <- object .: "insightIdentifier"
    dispatchReferenceText <- object .: "dispatchReference"
    traceText <- object .: "trace"
    traceUlid <- parseUlid traceText
    occurredAtValue <- object .: "occurredAt"
    pure
      InsightCollectedEvent
        { insightIdentifier = insightIdentifierText
        , dispatchReference = dispatchReferenceText
        , trace = Trace traceUlid
        , occurredAt = occurredAtValue
        }

instance FromJSON RetestRequestedEvent where
  parseJSON = withObject "RetestRequestedEvent" $ \object -> do
    retestIdentifierText <- object .: "retestIdentifier"
    dispatchReferenceText <- object .: "dispatchReference"
    traceText <- object .: "trace"
    traceUlid <- parseUlid traceText
    occurredAtValue <- object .: "occurredAt"
    pure
      RetestRequestedEvent
        { retestIdentifier = retestIdentifierText
        , dispatchReference = dispatchReferenceText
        , trace = Trace traceUlid
        , occurredAt = occurredAtValue
        }

-- | Parse a ULID from a JSON string value.
parseUlid :: (MonadFail m) => Text -> m ULID
parseUlid text =
  case readMaybe (Text.unpack text) of
    Nothing -> fail ("invalid ULID: " <> Text.unpack text)
    Just ulid -> pure ulid

-- ---------------------------------------------------------------------------
-- DomainError → PubSubPushResult mapping (Must-14)
-- ---------------------------------------------------------------------------

{- | Must-14: Map 'DomainError' to 'PubSubPushResult'.

 * 'AlreadyProcessed IdempotencyDuplicateEvent' → 'PubSubPushOrchestrationDuplicate' (200)
 * Non-retryable reason codes (ResourceNotFound, RequestValidationFailed)
   → 'PubSubPushSchemaInvalid' (200)
 * Everything else → 'PubSubPushOrchestrationFailed' (500)
-}
domainResultToPushResult :: Either DomainError () -> PubSubPushResult
domainResultToPushResult (Right ()) = PubSubPushOrchestrationSucceeded
domainResultToPushResult (Left domainError) =
  case domainError of
    AlreadyProcessed _ ->
      PubSubPushOrchestrationDuplicate
    InvariantViolation _ message reasonCode ->
      if isSatisfiedBy NonRetryableReasonSpecification reasonCode
        then PubSubPushSchemaInvalid message
        else PubSubPushOrchestrationFailed message
    MissingRequiredFields fields reasonCode ->
      let message = Text.intercalate ", " fields
       in if isSatisfiedBy NonRetryableReasonSpecification reasonCode
            then PubSubPushSchemaInvalid message
            else PubSubPushOrchestrationFailed message
    InvalidStateTransition from to reasonCode ->
      let message = from <> " \x2192 " <> to
       in if isSatisfiedBy NonRetryableReasonSpecification reasonCode
            then PubSubPushSchemaInvalid message
            else PubSubPushOrchestrationFailed message

-- ---------------------------------------------------------------------------
-- Logging helpers (Must-16, Must-17)
-- ---------------------------------------------------------------------------

logReceived :: LogEnv -> Maybe Text -> Maybe Text -> Text -> IO ()
logReceived logEnvironment traceValue identifierValue eventTypeValue =
  logInfoWith
    logEnvironment
    ( LogContext
        { service = "agent-orchestrator"
        , trace = traceValue
        , identifier = identifierValue
        , eventType = Just eventTypeValue
        , reasonCode = Nothing
        , result = Nothing
        , payloadSummary = Nothing
        }
    )
    "pubsub_push_received"

logResult :: LogEnv -> Maybe Text -> Maybe Text -> Text -> PubSubPushResult -> IO ()
logResult logEnvironment traceValue identifierValue eventTypeValue pushResult =
  let logFn = case pushResult of
        PubSubPushOrchestrationFailed _ -> logErrorWith
        _ -> logInfoWith
   in logFn
        logEnvironment
        ( LogContext
            { service = "agent-orchestrator"
            , trace = traceValue
            , identifier = identifierValue
            , eventType = Just eventTypeValue
            , reasonCode = Nothing
            , result = Just (pushResultLabel pushResult)
            , payloadSummary = Nothing
            }
        )
        "pubsub_push_processed"

logSchemaDecodeError :: LogEnv -> Text -> Maybe Text -> Maybe Text -> IO ()
logSchemaDecodeError logEnvironment errorMessage traceValue identifierValue =
  logErrorWith
    logEnvironment
    ( LogContext
        { service = "agent-orchestrator"
        , trace = traceValue
        , identifier = identifierValue
        , eventType = Nothing
        , reasonCode = Nothing
        , result = Just "schema_invalid"
        , payloadSummary = Nothing
        }
    )
    ("pubsub_decode_failed: " <> errorMessage)

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

pushResultLabel :: PubSubPushResult -> Text
pushResultLabel PubSubPushOrchestrationSucceeded = "orchestration_succeeded"
pushResultLabel PubSubPushOrchestrationDuplicate = "orchestration_duplicate"
pushResultLabel (PubSubPushSchemaInvalid _) = "schema_invalid"
pushResultLabel (PubSubPushUnknownEventType _) = "unknown_event_type"
pushResultLabel (PubSubPushOrchestrationFailed _) = "orchestration_failed"

encodeUtf8Lazy :: Text -> ByteString
encodeUtf8Lazy = ByteString.Lazy.fromStrict . Text.Encoding.encodeUtf8
