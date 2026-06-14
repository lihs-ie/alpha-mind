{- | Pub/Sub push endpoint handler for @operation.kill_switch.changed@ events.

 Implements @POST /pubsub/kill-switch@.

 Decode chain:
   1. Raw HTTP body → 'PubSubPushEnvelope' (JSON)
   2. @message.data@ base64 → raw bytes
   3. Raw bytes → 'CloudEvent Value' (decodePubSubPush @Value)
   4. Extract 'KillSwitchChangedPayload' from CloudEvent envelope + payload
   5. Call 'syncKillSwitch' via AppM with withRetry (Must-11)

 HTTP status mapping:
   * 'SyncKillSwitchApplied' / 'Duplicate' → 200 (ack)
   * schema invalid                         → 200 (ack, no re-delivery)
   * retryable failure (3 retries exceeded) → 500 (nack)
-}
module Presentation.Subscriber.PubSubKillSwitchSubscriber (
  -- * Result type
  KillSwitchPushResult (..),

  -- * Core logic (IO — testable without Servant)
  processKillSwitchMessageWith,
  processKillSwitchMessage,

  -- * Servant handler
  handleKillSwitchChanged,

  -- * HTTP status mapping
  killSwitchPushResultToStatus,
) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.Aeson.Types qualified as AesonTypes
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as ByteStringLazy
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.ULID (ULID)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (decodePubSubPush)
import Presentation.AppM (AppEnv (..), runAppM)
import Resilience.Retry (defaultRetryPolicyConfig, withRetry)
import Servant (Handler, ServerError (..), err500, throwError)
import UseCase.SyncKillSwitch (KillSwitchChangedPayload (..), SyncKillSwitchResult (..), syncKillSwitch)

-- ---------------------------------------------------------------------------
-- Result type
-- ---------------------------------------------------------------------------

data KillSwitchPushResult
  = KillSwitchApplied
  | KillSwitchDuplicate
  | KillSwitchSchemaInvalid Text
  | KillSwitchSyncFailed Text
  deriving stock (Eq, Show)

-- | Maps 'KillSwitchPushResult' to HTTP status.
killSwitchPushResultToStatus :: KillSwitchPushResult -> Either ServerError KillSwitchPushResult
killSwitchPushResultToStatus KillSwitchApplied = Right KillSwitchApplied
killSwitchPushResultToStatus KillSwitchDuplicate = Right KillSwitchDuplicate
killSwitchPushResultToStatus (KillSwitchSchemaInvalid message) = Right (KillSwitchSchemaInvalid message)
killSwitchPushResultToStatus (KillSwitchSyncFailed message) =
  Left err500{errBody = "kill_switch_sync_failed: " <> encodeUtf8Lazy message}

-- ---------------------------------------------------------------------------
-- Core logic (IO — injectable usecase runner for tests)
-- ---------------------------------------------------------------------------

{- | Process a Pub/Sub push body with an injectable usecase runner (seam).

 Must-11: withRetry for retryable failures (max 3, exponential backoff).
-}
processKillSwitchMessageWith ::
  (KillSwitchChangedPayload -> IO SyncKillSwitchResult) ->
  ByteString ->
  IO KillSwitchPushResult
processKillSwitchMessageWith runUseCase body =
  case decodePubSubPush @Value body of
    Left pubSubError ->
      pure (KillSwitchSchemaInvalid (Text.pack (show pubSubError)))
    Right (CloudEvent{identifier = eventIdentifier, trace = eventTrace, payload = eventPayload}) ->
      case extractKillSwitchPayload eventIdentifier eventTrace eventPayload of
        Left decodingError ->
          pure (KillSwitchSchemaInvalid decodingError)
        Right payload -> do
          retryResult <-
            withRetry
              defaultRetryPolicyConfig
              isRetryableSyncResult
              ( do
                  syncResult <- runUseCase payload
                  -- Retryable failures go to Left so withRetry can trigger on them.
                  -- Terminal results (including non-retryable failures) go to Right.
                  case syncResult of
                    SyncKillSwitchFailed message True -> pure (Left (SyncKillSwitchFailed message True))
                    other -> pure (Right other)
              )
          case retryResult of
            Left _ -> pure (KillSwitchSyncFailed "retry_exhausted")
            Right syncResult -> pure (syncResultToPushResult syncResult)
 where
  isRetryableSyncResult :: SyncKillSwitchResult -> Bool
  isRetryableSyncResult (SyncKillSwitchFailed _ True) = True
  isRetryableSyncResult _ = False

{- | Process a Pub/Sub push body for kill-switch events.

 Uses the real 'runAppM'-based runner.

 Must-02: Calls 'syncKillSwitch' from UseCase.SyncKillSwitch.
-}
processKillSwitchMessage ::
  AppEnv ->
  ByteString ->
  IO KillSwitchPushResult
processKillSwitchMessage appEnv =
  processKillSwitchMessageWith
    (runAppM appEnv . syncKillSwitch)

-- ---------------------------------------------------------------------------
-- Servant handler
-- ---------------------------------------------------------------------------

{- | Servant 'Handler' wrapper around 'processKillSwitchMessage'.

 Must-02: Calls handleKillSwitchChanged which calls syncKillSwitch.
-}
handleKillSwitchChanged ::
  AppEnv ->
  ByteString ->
  Handler KillSwitchPushResult
handleKillSwitchChanged appEnv body = do
  pushResult <- liftIO (processKillSwitchMessage appEnv body)
  case killSwitchPushResultToStatus pushResult of
    Left serverError -> throwError serverError
    Right successResult -> pure successResult

-- ---------------------------------------------------------------------------
-- CloudEvent payload extraction
-- ---------------------------------------------------------------------------

{- | Extract 'KillSwitchChangedPayload' from CloudEvent envelope fields.

 The CloudEvent identifier and trace are taken from the envelope (not payload).
 The @enabled@ field is extracted from the payload object.
-}
extractKillSwitchPayload :: ULID -> ULID -> Value -> Either Text KillSwitchChangedPayload
extractKillSwitchPayload cloudEventIdentifier cloudEventTrace payloadValue =
  case AesonTypes.parseEither parseEnabledField payloadValue of
    Left parseError -> Left (Text.pack parseError)
    Right enabledValue ->
      Right
        KillSwitchChangedPayload
          { identifier = cloudEventIdentifier
          , enabled = enabledValue
          , trace = cloudEventTrace
          }
 where
  parseEnabledField = Aeson.withObject "KillSwitchPayload" $ \objectValue ->
    objectValue Aeson..: "enabled"

-- ---------------------------------------------------------------------------
-- Result mapping
-- ---------------------------------------------------------------------------

syncResultToPushResult :: SyncKillSwitchResult -> KillSwitchPushResult
syncResultToPushResult SyncKillSwitchApplied = KillSwitchApplied
syncResultToPushResult SyncKillSwitchDuplicate = KillSwitchDuplicate
syncResultToPushResult (SyncKillSwitchFailed message False) = KillSwitchSchemaInvalid message
syncResultToPushResult (SyncKillSwitchFailed message True) = KillSwitchSyncFailed message

-- ---------------------------------------------------------------------------
-- Internal helper
-- ---------------------------------------------------------------------------

encodeUtf8Lazy :: Text -> ByteString
encodeUtf8Lazy = ByteStringLazy.fromStrict . TextEncoding.encodeUtf8
