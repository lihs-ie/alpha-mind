{- | Pub/Sub push endpoint handler for the data-collector service.

 Implements @POST /pubsub/events@.

 Decode chain:
   1. Raw HTTP body → 'PubSubPushEnvelope' (JSON)
   2. @message.data@ base64 → raw bytes
   3. Raw bytes → 'CloudEvent Value' (decodeCloudEvent)
   4. 'CloudEvent Value' → 'RawSourceEvent'
   5. Call 'collectMarketData'

 HTTP status mapping (RULE-DC-PRS-001):
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

  -- * Log context builder (exported for Must-14 tests)
  buildLogContext,

  -- * RawSourceEvent builder (exported for Must-05 tests)
  cloudEventToRawSourceEvent,
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
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (
  MarketCollectionIdentifier (..),
  RequestedBy (..),
 )
import Domain.MarketCollection.CollectionQualityPolicy (MarketSchemaIntegritySpecification)
import Domain.MarketCollection.SourcePolicySpecificationService (
  ApprovedSourceSpecification,
  DataSourceName (..),
 )
import Infrastructure.Wire.ReasonCodeWire (reasonCodeToWire)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubError, decodePubSubPush)
import Observability.Logging (LogContext (..), LogEnv, logErrorWith, logInfoWith)
import Presentation.AppM (AppEnv (..), runAppM)
import Servant (Handler, ServerError (..), err500, throwError)
import Text.Read (readMaybe)
import UseCase.CollectMarketData (
  CollectMarketDataResult (..),
  RawSourceEvent (..),
  collectMarketData,
 )

-- ---------------------------------------------------------------------------
-- Result type (Must-03)
-- ---------------------------------------------------------------------------

data PubSubPushResult
  = PubSubPushCollectionSucceeded
  | PubSubPushCollectionDuplicate
  | PubSubPushSchemaInvalid Text
  | PubSubPushWriteFailed Text
  | PubSubPushDomainError Text
  deriving stock (Eq, Show)

-- | Maps 'PubSubPushResult' to the HTTP status policy (RULE-DC-PRS-001).
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

 The usecase runner argument allows tests to substitute a fake implementation
 without any test code entering src/. The production wrapper 'processPubSubPush'
 passes the real 'runAppM'-based runner.

 Decode chain, logging, and result mapping are all performed here;
 only the usecase execution is parameterised.
-}
processPubSubPushWith ::
  LogEnv ->
  ApprovedSourceSpecification ->
  MarketSchemaIntegritySpecification ->
  ( UTCTime ->
    MarketCollectionIdentifier ->
    ApprovedSourceSpecification ->
    MarketSchemaIntegritySpecification ->
    RawSourceEvent ->
    IO CollectMarketDataResult
  ) ->
  ByteString ->
  IO PubSubPushResult
processPubSubPushWith logEnvironment approvedSources schemaSpecification runUseCase body =
  case decodePubSubPush @Value body of
    Left pubSubError -> do
      logSchemaInvalidError logEnvironment pubSubError Nothing Nothing
      pure (PubSubPushSchemaInvalid (Text.pack (show pubSubError)))
    Right cloudEvent -> do
      let rawSourceEvent = cloudEventToRawSourceEvent cloudEvent
          traceText = Just (Text.pack (show cloudEvent.trace))
          identifierText = Just (Text.pack (show cloudEvent.identifier))
      logReceived logEnvironment traceText identifierText cloudEvent.eventType
      currentTime <- getCurrentTime
      -- Design decision 5: collectionIdentifier is derived from the source event identifier
      -- so that re-delivery of the same event is deduplicated by CollectionDispatch.
      let collectionIdentifier = MarketCollectionIdentifier cloudEvent.identifier
      collectionResult <-
        runUseCase
          currentTime
          collectionIdentifier
          approvedSources
          schemaSpecification
          rawSourceEvent
      let pushResult = collectMarketDataResultToPushResult collectionResult
      logResult logEnvironment traceText identifierText cloudEvent.eventType pushResult
      pure pushResult

{- | Process a Pub/Sub push body, returning a 'PubSubPushResult'.

 This function runs entirely in 'IO' so it can be called directly from
 unit tests without requiring a Servant 'Handler' context.

 Delegates to 'processPubSubPushWith' with the real 'runAppM'-based runner.
-}
processPubSubPush ::
  AppEnv ->
  ByteString ->
  IO PubSubPushResult
processPubSubPush appEnv body =
  processPubSubPushWith
    appEnv.logEnv
    appEnv.approvedSourceSpecification
    appEnv.schemaIntegritySpecification
    ( \currentTime collectionIdentifier approvedSources schemaSpecification rawSourceEvent ->
        runAppM appEnv $
          collectMarketData
            currentTime
            collectionIdentifier
            approvedSources
            schemaSpecification
            rawSourceEvent
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
-- Conversion helpers (Must-05)
-- ---------------------------------------------------------------------------

{- | Convert a 'CloudEvent Value' to 'RawSourceEvent'.

 Extracts 'targetDate', 'requestedBy', and 'requestedSources' from the
 CloudEvent payload JSON. Missing or invalid fields are represented as
 'Nothing' / empty list; validation is deferred to the use case layer.
-}
cloudEventToRawSourceEvent :: CloudEvent Value -> RawSourceEvent
cloudEventToRawSourceEvent cloudEvent =
  let payloadValue = cloudEvent.payload
      maybeTargetDay = extractTargetDate payloadValue
      maybeRequestedBy = extractRequestedBy payloadValue
      requestedSourcesList = extractRequestedSources payloadValue
      traceValue = Trace cloudEvent.trace
   in RawSourceEvent
        { targetDate = maybeTargetDay
        , requestedBy = maybeRequestedBy
        , requestedSources = requestedSourcesList
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

extractRequestedSources :: Value -> [DataSourceName]
extractRequestedSources value =
  case Aeson.parseEither (Aeson..: "requestedSources") =<< asObject value of
    Left _ -> []
    Right names -> map DataSourceName names

asObject :: Value -> Either String Aeson.Object
asObject (Aeson.Object objectValue) = Right objectValue
asObject _ = Left "payload is not an object"

parseRequestedBy :: Text -> Maybe RequestedBy
parseRequestedBy "scheduler" = Just Scheduler
parseRequestedBy "user" = Just User
parseRequestedBy _ = Nothing

-- ---------------------------------------------------------------------------
-- Result mapping (Must-04)
-- ---------------------------------------------------------------------------

collectMarketDataResultToPushResult :: CollectMarketDataResult -> PubSubPushResult
collectMarketDataResultToPushResult CollectionSucceeded = PubSubPushCollectionSucceeded
collectMarketDataResultToPushResult CollectionDuplicate = PubSubPushCollectionDuplicate
collectMarketDataResultToPushResult (CollectionFailed reasonCode False) =
  -- Non-retryable: ack with 200, do not re-deliver
  PubSubPushSchemaInvalid (reasonCodeToWire reasonCode)
collectMarketDataResultToPushResult (CollectionFailed reasonCode True) =
  -- Retryable: nack with 500, Pub/Sub will re-deliver
  PubSubPushWriteFailed (reasonCodeToWire reasonCode)

-- ---------------------------------------------------------------------------
-- Log context builder (Must-12, Must-14 — exported for tests)
-- ---------------------------------------------------------------------------

{- | Build a 'LogContext' for the data-collector service.

 Exported so tests can verify the 'service', 'trace', and 'identifier' fields
 without a live 'LogEnv' (Must-14).
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
    { service = "data-collector"
    , trace = traceValue
    , identifier = identifierValue
    , eventType = Just eventTypeValue
    , reasonCode = reasonCodeValue
    , result = resultValue
    , payloadSummary = Nothing
    }

-- ---------------------------------------------------------------------------
-- Logging helpers (Must-12)
-- ---------------------------------------------------------------------------

logReceived :: LogEnv -> Maybe Text -> Maybe Text -> Text -> IO ()
logReceived logEnvironment traceValue identifierValue eventTypeValue =
  logInfoWith
    logEnvironment
    ( LogContext
        { service = "data-collector"
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
        { service = "data-collector"
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
        { service = "data-collector"
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
