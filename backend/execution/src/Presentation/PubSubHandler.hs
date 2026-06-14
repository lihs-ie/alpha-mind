{- | Pub/Sub push endpoint handler for the execution service.

 Implements @POST /pubsub/orders-approved@.

 Decode chain:
   1. Raw HTTP body → 'PubSubPushEnvelope' (JSON)
   2. @message.data@ base64 → raw bytes
   3. Raw bytes → 'CloudEvent Value' (decodePubSubPush)
   4. 'CloudEvent Value' → 'ApprovedOrderEvent'
   5. Call 'executeOrder'

 HTTP status mapping (RULE-EX-PRS-001):
   * 'PubSubPushExecutionSucceeded'  → 200 (success)
   * 'PubSubPushExecutionDuplicate'  → 200 (idempotent; no re-delivery needed)
   * 'PubSubPushSchemaInvalid'       → 200 (permanent decode failure; re-delivery loops)
   * 'PubSubPushExecutionRetryable'  → 500 (transient; Pub/Sub will re-deliver)
   * 'PubSubPushExecutionFailed'     → 200 (permanent failure; acknowledged, no retry)
-}
module Presentation.PubSubHandler (
  -- * Core logic (IO, usable in unit tests)
  processOrdersApproved,

  -- * Seam (injectable usecase runner for unit tests)
  processOrdersApprovedWith,

  -- * Servant handler
  handleOrdersApproved,

  -- * Result type
  PubSubPushResult (..),

  -- * HTTP status mapping
  pubSubPushResultToStatus,

  -- * Log context builder (exported for tests)
  buildLogContext,

  -- * ApprovedOrderEvent builder (exported for tests)
  cloudEventToApprovedOrderEvent,
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
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.Aggregate (
  ExecutionRequest (..),
  OrderExecutionIdentifier (..),
 )
import Infrastructure.Wire.ReasonCodeWire (reasonCodeToWire)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (decodePubSubPush)
import Observability.Logging (LogContext (..), LogEnv, logErrorWith, logInfoWith)
import Presentation.AppM (AppEnv (..), runAppM)
import Servant (Handler, ServerError (..), err500, throwError)
import Text.Read (readMaybe)
import UseCase.ExecuteOrder (
  ApprovedOrderEvent (..),
  ExecuteOrderResult (..),
  executeOrder,
 )

-- ---------------------------------------------------------------------------
-- Result type (RULE-EX-PRS-001)
-- ---------------------------------------------------------------------------

data PubSubPushResult
  = PubSubPushExecutionSucceeded
  | PubSubPushExecutionDuplicate
  | PubSubPushSchemaInvalid Text
  | PubSubPushExecutionRetryable Text
  | PubSubPushExecutionFailed Text
  deriving stock (Eq, Show)

-- | Maps 'PubSubPushResult' to the HTTP status policy (RULE-EX-PRS-001).
pubSubPushResultToStatus :: PubSubPushResult -> Either ServerError PubSubPushResult
pubSubPushResultToStatus PubSubPushExecutionSucceeded = Right PubSubPushExecutionSucceeded
pubSubPushResultToStatus PubSubPushExecutionDuplicate = Right PubSubPushExecutionDuplicate
pubSubPushResultToStatus (PubSubPushSchemaInvalid message) = Right (PubSubPushSchemaInvalid message)
pubSubPushResultToStatus (PubSubPushExecutionRetryable message) =
  Left err500{errBody = "execution_retryable: " <> encodeUtf8Lazy message}
pubSubPushResultToStatus (PubSubPushExecutionFailed message) = Right (PubSubPushExecutionFailed message)

-- ---------------------------------------------------------------------------
-- Core logic (IO — injectable seam for tests)
-- ---------------------------------------------------------------------------

{- | Process a Pub/Sub push body with an injectable usecase runner (seam).

 The usecase runner argument allows tests to substitute a fake implementation
 without any test code entering src/. The production wrapper
 'processOrdersApproved' passes the real 'runAppM'-based runner.
-}
processOrdersApprovedWith ::
  LogEnv ->
  (UTCTime -> ApprovedOrderEvent -> IO ExecuteOrderResult) ->
  ByteString ->
  IO PubSubPushResult
processOrdersApprovedWith logEnvironment runUseCase body =
  case decodePubSubPush @Value body of
    Left pubSubError -> do
      logDecodeError logEnvironment (Text.pack (show pubSubError)) Nothing Nothing
      pure (PubSubPushSchemaInvalid (Text.pack (show pubSubError)))
    Right cloudEvent ->
      let traceText = Just (Text.pack (show cloudEvent.trace))
          identifierText = Just (Text.pack (show cloudEvent.identifier))
       in case cloudEventToApprovedOrderEvent cloudEvent of
            Left decodeError -> do
              logDecodeError logEnvironment decodeError traceText identifierText
              pure (PubSubPushSchemaInvalid decodeError)
            Right approvedOrderEvent -> do
              logReceived logEnvironment traceText identifierText cloudEvent.eventType
              currentTime <- getCurrentTime
              executeOrderResult <- runUseCase currentTime approvedOrderEvent
              let pushResult = executeOrderResultToPushResult executeOrderResult
              logResult logEnvironment traceText identifierText cloudEvent.eventType pushResult
              pure pushResult

{- | Process a Pub/Sub push body, returning a 'PubSubPushResult'.

 Runs entirely in 'IO' so it can be called from unit tests without a
 Servant 'Handler' context. Delegates to 'processOrdersApprovedWith'
 with the real 'runAppM'-based runner.
-}
processOrdersApproved ::
  AppEnv ->
  ByteString ->
  IO PubSubPushResult
processOrdersApproved appEnv body =
  processOrdersApprovedWith
    appEnv.logEnv
    (\currentTime approvedOrderEvent -> runAppM appEnv (executeOrder currentTime approvedOrderEvent))
    body

-- ---------------------------------------------------------------------------
-- Servant handler (delegates to processOrdersApproved)
-- ---------------------------------------------------------------------------

{- | Servant 'Handler' wrapper around 'processOrdersApproved'.

 Translates 'PubSubPushResult' to the appropriate HTTP status via
 'pubSubPushResultToStatus'.
-}
handleOrdersApproved ::
  AppEnv ->
  ByteString ->
  Handler PubSubPushResult
handleOrdersApproved appEnv body = do
  pushResult <- liftIO (processOrdersApproved appEnv body)
  case pubSubPushResultToStatus pushResult of
    Left serverError -> throwError serverError
    Right successResult -> pure successResult

-- ---------------------------------------------------------------------------
-- Conversion helpers
-- ---------------------------------------------------------------------------

{- | Convert a 'CloudEvent Value' to 'ApprovedOrderEvent'.

 Extracts 'identifier' (ULID), 'symbol', 'side', 'qty' from the payload.
 The 'orders.approved' payload carries the execution identifier and order
 item details needed to construct 'ExecutionRequest'.

 Missing or malformed fields return 'Left' with an error description.
-}
cloudEventToApprovedOrderEvent :: CloudEvent Value -> Either Text ApprovedOrderEvent
cloudEventToApprovedOrderEvent cloudEvent =
  case Aeson.parseEither parsePayloadFields cloudEvent.payload of
    Left parseError -> Left (Text.pack parseError)
    Right (executionIdentifier, executionRequest) ->
      Right
        ApprovedOrderEvent
          { identifier = executionIdentifier
          , request = executionRequest
          , trace = Trace cloudEvent.trace
          , occurredAt = cloudEvent.occurredAt
          }

parsePayloadFields :: Value -> Aeson.Parser (OrderExecutionIdentifier, ExecutionRequest)
parsePayloadFields = Aeson.withObject "ApprovedOrderPayload" $ \objectValue -> do
  identifierText <- objectValue Aeson..: "identifier"
  case readMaybe (Text.unpack identifierText) :: Maybe ULID of
    Nothing ->
      fail ("invalid identifier ULID: " <> Text.unpack identifierText)
    Just ulidValue -> do
      symbolValue <- objectValue Aeson..: "symbol"
      sideValue <- objectValue Aeson..: "side"
      qtyValue <- objectValue Aeson..: "qty"
      pure
        ( OrderExecutionIdentifier{value = ulidValue}
        , ExecutionRequest{symbol = symbolValue, side = sideValue, qty = qtyValue}
        )

-- ---------------------------------------------------------------------------
-- Result mapping (RULE-EX-PRS-001)
-- ---------------------------------------------------------------------------

executeOrderResultToPushResult :: ExecuteOrderResult -> PubSubPushResult
executeOrderResultToPushResult ExecuteOrderSucceeded = PubSubPushExecutionSucceeded
executeOrderResultToPushResult ExecuteOrderDuplicate = PubSubPushExecutionDuplicate
executeOrderResultToPushResult ExecuteOrderRetryable = PubSubPushExecutionRetryable "retryable"
executeOrderResultToPushResult (ExecuteOrderFailed reasonCode True) =
  PubSubPushExecutionRetryable (reasonCodeToWire reasonCode)
executeOrderResultToPushResult (ExecuteOrderFailed reasonCode False) =
  PubSubPushExecutionFailed (reasonCodeToWire reasonCode)

-- ---------------------------------------------------------------------------
-- Log context builder (exported for tests)
-- ---------------------------------------------------------------------------

{- | Build a 'LogContext' for the execution service.

 Exported so tests can verify the 'service', 'trace', and 'identifier'
 fields without a live 'LogEnv'.
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
    { service = "execution"
    , trace = traceValue
    , identifier = identifierValue
    , eventType = Just eventTypeValue
    , reasonCode = reasonCodeValue
    , result = resultValue
    , payloadSummary = Nothing
    }

-- ---------------------------------------------------------------------------
-- Logging helpers
-- ---------------------------------------------------------------------------

logReceived :: LogEnv -> Maybe Text -> Maybe Text -> Text -> IO ()
logReceived logEnvironment traceValue identifierValue eventTypeValue =
  logInfoWith
    logEnvironment
    LogContext
      { service = "execution"
      , trace = traceValue
      , identifier = identifierValue
      , eventType = Just eventTypeValue
      , reasonCode = Nothing
      , result = Nothing
      , payloadSummary = Nothing
      }
    "pubsub_push_received"

logResult :: LogEnv -> Maybe Text -> Maybe Text -> Text -> PubSubPushResult -> IO ()
logResult logEnvironment traceValue identifierValue eventTypeValue pushResult =
  logInfoWith
    logEnvironment
    LogContext
      { service = "execution"
      , trace = traceValue
      , identifier = identifierValue
      , eventType = Just eventTypeValue
      , reasonCode = Nothing
      , result = Just (pushResultLabel pushResult)
      , payloadSummary = Nothing
      }
    "pubsub_push_processed"

logDecodeError :: LogEnv -> Text -> Maybe Text -> Maybe Text -> IO ()
logDecodeError logEnvironment errorMessage traceValue identifierValue =
  logErrorWith
    logEnvironment
    LogContext
      { service = "execution"
      , trace = traceValue
      , identifier = identifierValue
      , eventType = Nothing
      , reasonCode = Nothing
      , result = Just "schema_invalid"
      , payloadSummary = Nothing
      }
    ("pubsub_decode_failed: " <> errorMessage)

pushResultLabel :: PubSubPushResult -> Text
pushResultLabel PubSubPushExecutionSucceeded = "execution_succeeded"
pushResultLabel PubSubPushExecutionDuplicate = "execution_duplicate"
pushResultLabel (PubSubPushSchemaInvalid _) = "schema_invalid"
pushResultLabel (PubSubPushExecutionRetryable _) = "execution_retryable"
pushResultLabel (PubSubPushExecutionFailed _) = "execution_failed"

-- ---------------------------------------------------------------------------
-- Internal helper
-- ---------------------------------------------------------------------------

encodeUtf8Lazy :: Text -> ByteString
encodeUtf8Lazy = ByteStringLazy.fromStrict . TextEncoding.encodeUtf8
