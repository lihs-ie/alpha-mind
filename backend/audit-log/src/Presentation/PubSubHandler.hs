{- | Pub/Sub push endpoint handler for the audit-log service.

 Implements @POST /pubsub/events@.

 Decode chain:
   1. Raw HTTP body → 'PubSubPushEnvelope' (JSON)
   2. @message.data@ base64 → raw bytes
   3. Raw bytes → 'CloudEvent Value' (decodeCloudEvent)
   4. 'CloudEvent Value' → 'RawSourceEvent'
   5. Call 'recordAuditFromSourceEvent'

 HTTP status mapping (RULE-AU-007):
   * 'Recorded'                → 200  (success; no re-delivery needed)
   * 'Duplicate'               → 200  (idempotent; no re-delivery needed)
   * 'SchemaInvalid'           → 200  (permanent validation failure; re-delivery would repeat the error)
   * 'WriteFailed'             → 500  (transient; Pub/Sub will re-deliver)
   * 'RecordAuditDomainError'  → 500  (transient domain error; Pub/Sub will re-deliver)

 Pub/Sub push decode errors (JSON invalid, base64 invalid, CloudEvent invalid)
 are treated as 'SchemaInvalid' and return 200 to prevent re-delivery loops.
-}
module Presentation.PubSubHandler (
  -- * Core logic (IO, usable in unit tests)
  processPubSubPush,

  -- * Servant handler
  handlePubSubPush,

  -- * Result type
  PubSubPushResult (..),

  -- * HTTP status mapping
  pubSubPushResultToStatus,
) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value)
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as ByteStringLazy
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time (getCurrentTime)
import Domain.AuditLog.AuditIngestion (AuditIngestionIdentifier (..))
import Domain.AuditLog.AuditRecord (AuditRecordIdentifier (..))
import Domain.AuditLog.Specification (RawSourceEvent (..))
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubError, decodePubSubPush)
import Observability.Logging (LogContext (..), LogEnv, logErrorWith, logInfoWith)
import Presentation.AppM (AppEnv (..), runAppM)
import Servant (Handler, ServerError (..), err500, throwError)
import UseCase.RecordAuditFromSourceEvent (RecordAuditResult (..), recordAuditFromSourceEvent)

-- ---------------------------------------------------------------------------
-- Result type
-- ---------------------------------------------------------------------------

data PubSubPushResult
  = PubSubPushRecorded
  | PubSubPushDuplicate
  | PubSubPushSchemaInvalid Text
  | PubSubPushWriteFailed Text
  | PubSubPushDomainError Text
  deriving stock (Eq, Show)

-- | Maps 'PubSubPushResult' to the HTTP status policy (RULE-AU-007).
pubSubPushResultToStatus :: PubSubPushResult -> Either ServerError PubSubPushResult
pubSubPushResultToStatus PubSubPushRecorded = Right PubSubPushRecorded
pubSubPushResultToStatus PubSubPushDuplicate = Right PubSubPushDuplicate
pubSubPushResultToStatus (PubSubPushSchemaInvalid message) = Right (PubSubPushSchemaInvalid message)
pubSubPushResultToStatus (PubSubPushWriteFailed message) = Left err500{errBody = "write_failed: " <> encodeUtf8Lazy message}
pubSubPushResultToStatus (PubSubPushDomainError message) = Left err500{errBody = "domain_error: " <> encodeUtf8Lazy message}

-- ---------------------------------------------------------------------------
-- Core logic (IO — testable without Servant)
-- ---------------------------------------------------------------------------

{- | Process a Pub/Sub push body, returning a 'PubSubPushResult'.

 This function runs entirely in 'IO' so it can be called directly from
 unit tests without requiring a Servant 'Handler' context.
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
      let rawSourceEvent = cloudEventToRawSourceEvent cloudEvent
          traceText = Just (Text.pack (show cloudEvent.trace))
          identifierText = Just (Text.pack (show cloudEvent.identifier))
      logReceived appEnv.logEnv traceText identifierText cloudEvent.eventType
      currentTime <- getCurrentTime
      -- RULE-AU-002 / 設計 §8: 識別子はソースイベント identifier (冪等キー) から導出する。
      -- audit_logs/{identifier} と idempotency_keys/{identifier} は同一イベント identifier で索引する。
      -- リクエスト毎に新規 ULID を採番すると同一イベント再送で dedup が効かない。
      let recordIdentifier = AuditRecordIdentifier cloudEvent.identifier
          ingestionIdentifier = AuditIngestionIdentifier cloudEvent.identifier
      auditResult <-
        runAppM appEnv $
          recordAuditFromSourceEvent
            currentTime
            recordIdentifier
            ingestionIdentifier
            rawSourceEvent
            "audit-log"
      let pushResult = recordAuditResultToPushResult auditResult
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
-- Conversion helpers
-- ---------------------------------------------------------------------------

cloudEventToRawSourceEvent :: CloudEvent Value -> RawSourceEvent
cloudEventToRawSourceEvent cloudEvent =
  RawSourceEvent
    { identifier = Just cloudEvent.identifier
    , eventType = Just cloudEvent.eventType
    , occurredAt = Just cloudEvent.occurredAt
    , trace = Just cloudEvent.trace
    , payload = Just cloudEvent.payload
    }

recordAuditResultToPushResult :: RecordAuditResult -> PubSubPushResult
recordAuditResultToPushResult Recorded = PubSubPushRecorded
recordAuditResultToPushResult Duplicate = PubSubPushDuplicate
recordAuditResultToPushResult (SchemaInvalid domainError) =
  PubSubPushSchemaInvalid (Text.pack (show domainError))
recordAuditResultToPushResult (WriteFailed message) =
  PubSubPushWriteFailed message
recordAuditResultToPushResult (RecordAuditDomainError domainError) =
  PubSubPushDomainError (Text.pack (show domainError))

-- ---------------------------------------------------------------------------
-- Logging helpers (Must-6: all log entries include trace/identifier/service)
-- ---------------------------------------------------------------------------

logReceived :: LogEnv -> Maybe Text -> Maybe Text -> Text -> IO ()
logReceived logEnvironment traceValue identifierValue eventTypeValue =
  logInfoWith
    logEnvironment
    ( LogContext
        { service = "audit-log"
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
        { service = "audit-log"
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
        { service = "audit-log"
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
pushResultLabel PubSubPushRecorded = "recorded"
pushResultLabel PubSubPushDuplicate = "duplicate"
pushResultLabel (PubSubPushSchemaInvalid _) = "schema_invalid"
pushResultLabel (PubSubPushWriteFailed _) = "write_failed"
pushResultLabel (PubSubPushDomainError _) = "domain_error"

-- ---------------------------------------------------------------------------
-- Internal helper
-- ---------------------------------------------------------------------------

encodeUtf8Lazy :: Text -> ByteString
encodeUtf8Lazy = ByteStringLazy.fromStrict . TextEncoding.encodeUtf8
