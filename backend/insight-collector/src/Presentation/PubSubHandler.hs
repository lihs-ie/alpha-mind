{- | Pub/Sub push endpoint handler for the insight-collector service.

 Implements @POST /pubsub/events@.

 Decode chain:
   1. Raw HTTP body → 'PubSubPushEnvelope' (JSON)
   2. @message.data@ base64 → raw bytes
   3. Raw bytes → 'CloudEvent Value' (decodeCloudEvent)
   4. 'CloudEvent Value' → 'RawInsightEvent'
   5. Call idempotency reserve, then 'collectInsights'

 HTTP status mapping (RULE-IC-PRS-001):
   * 'PubSubPushCollectionSucceeded'  → 200 (success; no re-delivery needed)
   * 'PubSubPushCollectionDuplicate'  → 200 (idempotent; no re-delivery needed)
   * 'PubSubPushSchemaInvalid'        → 200 (permanent validation failure; re-delivery would repeat the error)
   * 'PubSubPushWriteFailed'          → 500 (transient; Pub/Sub will re-deliver)
   * 'PubSubPushDomainError'          → 500 (transient domain error; Pub/Sub will re-deliver)

 Pub/Sub push decode errors (JSON invalid, base64 invalid, CloudEvent invalid)
 are treated as 'PubSubPushSchemaInvalid' and return 200 to prevent re-delivery loops.
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

  -- * Log context builder (exported for Must-12 tests)
  buildLogContext,

  -- * RawInsightEvent builder (exported for Must-02 tests)
  cloudEventToRawInsightEvent,
) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.Aeson.Types qualified as Aeson
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as ByteStringLazy
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time (Day, UTCTime, getCurrentTime)
import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (
  CollectionOptions (..),
  InsightCollectionIdentifier (..),
  RequestedBy (..),
  SourceType (..),
 )
import Infrastructure.Idempotency.InsightIdempotency (
  completeInsightIdempotency,
  reserveInsightIdempotency,
 )
import Infrastructure.Wire.ReasonCodeWire (reasonCodeToWire)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubError, decodePubSubPush)
import Observability.Logging (LogContext (..), LogEnv, logErrorWith, logInfoWith)
import Persistence.Idempotency (ReserveResult (..))
import Presentation.AppM (AppEnv (..), runAppM)
import Servant (Handler, ServerError (..), err500, throwError)
import Text.Read (readMaybe)
import UseCase.CollectInsights (
  CollectInsightsResult (..),
  RawInsightEvent (..),
  collectInsights,
 )

-- ---------------------------------------------------------------------------
-- Result type (MUST-06)
-- ---------------------------------------------------------------------------

data PubSubPushResult
  = PubSubPushCollectionSucceeded
  | PubSubPushCollectionDuplicate
  | PubSubPushSchemaInvalid Text
  | PubSubPushWriteFailed Text
  | PubSubPushDomainError Text
  deriving stock (Eq, Show)

-- | Maps 'PubSubPushResult' to the HTTP status policy (RULE-IC-PRS-001).
pubSubPushResultToStatus :: PubSubPushResult -> Either ServerError PubSubPushResult
pubSubPushResultToStatus PubSubPushCollectionSucceeded = Right PubSubPushCollectionSucceeded
pubSubPushResultToStatus PubSubPushCollectionDuplicate = Right PubSubPushCollectionDuplicate
pubSubPushResultToStatus (PubSubPushSchemaInvalid message) = Right (PubSubPushSchemaInvalid message)
pubSubPushResultToStatus (PubSubPushWriteFailed message) = Left err500{errBody = "write_failed: " <> encodeUtf8Lazy message}
pubSubPushResultToStatus (PubSubPushDomainError message) = Left err500{errBody = "domain_error: " <> encodeUtf8Lazy message}

-- ---------------------------------------------------------------------------
-- Core logic (IO — testable without Servant)
-- ---------------------------------------------------------------------------

{- | Process a Pub/Sub push body with an injectable usecase runner (seam).

 The usecase runner argument allows tests to substitute an implementation
 without any test code entering src/. The production wrapper 'processPubSubPush'
 passes the real 'runAppM'-based runner.

 Decode chain, logging, idempotency, and result mapping are all performed here;
 only the usecase execution is parameterised.
-}
processPubSubPushWith ::
  LogEnv ->
  (UTCTime -> InsightCollectionIdentifier -> RawInsightEvent -> IO CollectInsightsResult) ->
  ByteString ->
  IO PubSubPushResult
processPubSubPushWith logEnvironment runUseCase body =
  case decodePubSubPush @Value body of
    Left pubSubError -> do
      logSchemaInvalidError logEnvironment pubSubError Nothing Nothing
      pure (PubSubPushSchemaInvalid (Text.pack (show pubSubError)))
    Right cloudEvent -> do
      let rawInsightEvent = cloudEventToRawInsightEvent cloudEvent
          traceText = Just (Text.pack (show cloudEvent.trace))
          identifierText = Just (Text.pack (show cloudEvent.identifier))
      logReceived logEnvironment traceText identifierText cloudEvent.eventType
      currentTime <- getCurrentTime
      let collectionIdentifier = InsightCollectionIdentifier cloudEvent.identifier
      collectionResult <-
        runUseCase
          currentTime
          collectionIdentifier
          rawInsightEvent
      let pushResult = collectInsightsResultToPushResult collectionResult
      logResult logEnvironment traceText identifierText cloudEvent.eventType pushResult
      pure pushResult

{- | Process a Pub/Sub push body, returning a 'PubSubPushResult'.

 This function runs entirely in 'IO' so it can be called directly from
 unit tests without requiring a Servant 'Handler' context.

 Calls 'reserveInsightIdempotency' at the boundary before the use case (MUST-04).
 Calls 'completeInsightIdempotency' on success (MUST-05).
 Delegates to 'processPubSubPushWith' with the real 'runAppM'-based runner.
-}
processPubSubPush ::
  AppEnv ->
  ByteString ->
  IO PubSubPushResult
processPubSubPush appEnv body =
  case decodePubSubPush @Value body of
    Left pubSubError -> do
      logSchemaInvalidError appEnv.logEnv pubSubError Nothing Nothing
      pure (PubSubPushSchemaInvalid (Text.pack (show pubSubError)))
    Right cloudEvent -> do
      let collectionIdentifier = InsightCollectionIdentifier cloudEvent.identifier
          traceValue = Trace cloudEvent.trace
          traceText = Just (Text.pack (show cloudEvent.trace))
          identifierText = Just (Text.pack (show cloudEvent.identifier))
      logReceived appEnv.logEnv traceText identifierText cloudEvent.eventType
      -- MUST-04: Reserve idempotency key at boundary
      reserveResult <- reserveInsightIdempotency appEnv.firestoreContext collectionIdentifier traceValue
      case reserveResult of
        Right AlreadyProcessed ->
          pure PubSubPushCollectionDuplicate
        _ -> do
          currentTime <- getCurrentTime
          let rawInsightEvent = cloudEventToRawInsightEvent cloudEvent
          collectionResult <-
            runAppM appEnv $
              collectInsights
                currentTime
                collectionIdentifier
                rawInsightEvent
          let pushResult = collectInsightsResultToPushResult collectionResult
          -- MUST-05: Complete idempotency on success
          case pushResult of
            PubSubPushCollectionSucceeded -> do
              _ <- completeInsightIdempotency appEnv.firestoreContext collectionIdentifier
              pure ()
            _ -> pure ()
          logResult appEnv.logEnv traceText identifierText cloudEvent.eventType pushResult
          pure pushResult

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
-- Conversion helpers (MUST-02)
-- ---------------------------------------------------------------------------

{- | Convert a 'CloudEvent Value' to 'RawInsightEvent'.

 Extracts 'targetDate', 'requestedBy', 'requestedSourceTypes', 'options',
 and 'trace' from the CloudEvent payload JSON.
 Missing or invalid fields are represented as 'Nothing' / empty list;
 validation is deferred to the use case layer.
-}
cloudEventToRawInsightEvent :: CloudEvent Value -> RawInsightEvent
cloudEventToRawInsightEvent cloudEvent =
  let payloadValue = cloudEvent.payload
      maybeTargetDay = extractTargetDate payloadValue
      maybeRequestedBy = extractRequestedBy payloadValue
      requestedSourceTypesList = extractRequestedSourceTypes payloadValue
      maybeOptions = extractOptions payloadValue
      traceValue = Trace cloudEvent.trace
   in RawInsightEvent
        { targetDate = maybeTargetDay
        , requestedBy = maybeRequestedBy
        , requestedSourceTypes = requestedSourceTypesList
        , options = maybeOptions
        , trace = Just traceValue
        }

extractTargetDate :: Value -> Maybe Day
extractTargetDate value =
  case Aeson.parseEither (Aeson..: "targetDate") =<< asObject value of
    Left _ -> Nothing
    Right dateText -> readMaybe (Text.unpack dateText)

extractRequestedBy :: Value -> Maybe RequestedBy
extractRequestedBy value =
  case Aeson.parseEither (Aeson..: "requestedBy") =<< asObject value of
    Left _ -> Nothing
    Right text -> parseRequestedBy text

extractRequestedSourceTypes :: Value -> [SourceType]
extractRequestedSourceTypes value =
  case Aeson.parseEither (Aeson..: "requestedSourceTypes") =<< asObject value of
    Left _ -> []
    Right names -> mapMaybeSourceType names

extractOptions :: Value -> Maybe CollectionOptions
extractOptions value =
  case Aeson.parseEither (Aeson..: "options") =<< asObject value of
    Left _ -> Nothing
    Right optionsValue -> parseOptions optionsValue

parseOptions :: Value -> Maybe CollectionOptions
parseOptions value =
  case Aeson.parseEither parseCollectionOptions value of
    Left _ -> Nothing
    Right opts -> Just opts
 where
  parseCollectionOptions = Aeson.withObject "CollectionOptions" $ \obj -> do
    forceRecollectValue <- obj Aeson..:? "forceRecollect" Aeson..!= False
    dryRunValue <- obj Aeson..:? "dryRun" Aeson..!= False
    maxItemsPerSourceValue <- obj Aeson..:? "maxItemsPerSource"
    pure
      CollectionOptions
        { forceRecollect = forceRecollectValue
        , dryRun = dryRunValue
        , maxItemsPerSource = maxItemsPerSourceValue
        }

asObject :: Value -> Either String Aeson.Object
asObject (Aeson.Object objectValue) = Right objectValue
asObject _ = Left "payload is not an object"

parseRequestedBy :: Text -> Maybe RequestedBy
parseRequestedBy "scheduler" = Just Scheduler
parseRequestedBy "user" = Just User
parseRequestedBy _ = Nothing

parseSourceType :: Text -> Maybe SourceType
parseSourceType "X" = Just X
parseSourceType "YouTube" = Just YouTube
parseSourceType "Paper" = Just Paper
parseSourceType "GitHub" = Just GitHub
parseSourceType _ = Nothing

mapMaybeSourceType :: [Text] -> [SourceType]
mapMaybeSourceType = foldr (\t acc -> maybe acc (: acc) (parseSourceType t)) []

-- ---------------------------------------------------------------------------
-- Result mapping (MUST-06)
-- ---------------------------------------------------------------------------

collectInsightsResultToPushResult :: CollectInsightsResult -> PubSubPushResult
collectInsightsResultToPushResult CollectionSucceeded = PubSubPushCollectionSucceeded
collectInsightsResultToPushResult CollectionDuplicate = PubSubPushCollectionDuplicate
collectInsightsResultToPushResult (CollectionFailed reasonCode False) =
  -- Non-retryable: ack with 200, do not re-deliver
  PubSubPushSchemaInvalid (reasonCodeToWire reasonCode)
collectInsightsResultToPushResult (CollectionFailed reasonCode True) =
  -- Retryable: nack with 500, Pub/Sub will re-deliver
  PubSubPushWriteFailed (reasonCodeToWire reasonCode)

-- ---------------------------------------------------------------------------
-- Log context builder (MUST-12 — exported for tests)
-- ---------------------------------------------------------------------------

{- | Build a 'LogContext' for the insight-collector service.

 Exported so tests can verify the 'service', 'trace', and 'identifier' fields
 without a live 'LogEnv' (MUST-12).
-}
buildLogContext ::
  Text ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  LogContext
buildLogContext eventTypeValue traceValue identifierValue resultValue reasonCodeValue =
  LogContext
    { service = "insight-collector"
    , trace = traceValue
    , identifier = identifierValue
    , eventType = Just eventTypeValue
    , reasonCode = reasonCodeValue
    , result = resultValue
    , payloadSummary = Nothing
    }

-- ---------------------------------------------------------------------------
-- Logging helpers (MUST-12)
-- ---------------------------------------------------------------------------

logReceived :: LogEnv -> Maybe Text -> Maybe Text -> Text -> IO ()
logReceived logEnvironment traceValue identifierValue eventTypeValue =
  logInfoWith
    logEnvironment
    ( LogContext
        { service = "insight-collector"
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
  logInfoWith
    logEnvironment
    ( LogContext
        { service = "insight-collector"
        , trace = traceValue
        , identifier = identifierValue
        , eventType = Just eventTypeValue
        , reasonCode = Nothing
        , result = Just (pushResultLabel pushResult)
        , payloadSummary = Nothing
        }
    )
    "pubsub_push_processed"

logSchemaInvalidError :: LogEnv -> PubSubError -> Maybe Text -> Maybe Text -> IO ()
logSchemaInvalidError logEnvironment pubSubError traceValue identifierValue =
  logErrorWith
    logEnvironment
    ( LogContext
        { service = "insight-collector"
        , trace = traceValue
        , identifier = identifierValue
        , eventType = Nothing
        , reasonCode = Nothing
        , result = Just "schema_invalid"
        , payloadSummary = Nothing
        }
    )
    ("pubsub_decode_failed: " <> Text.pack (show pubSubError))

pushResultLabel :: PubSubPushResult -> Text
pushResultLabel PubSubPushCollectionSucceeded = "collection_succeeded"
pushResultLabel PubSubPushCollectionDuplicate = "collection_duplicate"
pushResultLabel (PubSubPushSchemaInvalid _) = "schema_invalid"
pushResultLabel (PubSubPushWriteFailed _) = "write_failed"
pushResultLabel (PubSubPushDomainError _) = "domain_error"

-- ---------------------------------------------------------------------------
-- Internal helper
-- ---------------------------------------------------------------------------

encodeUtf8Lazy :: Text -> ByteString
encodeUtf8Lazy = ByteStringLazy.fromStrict . TextEncoding.encodeUtf8
