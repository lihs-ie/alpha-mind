{-# OPTIONS_GHC -fno-hpc #-}

{- | Integration tests for the @POST /pubsub/events@ endpoint.

 Must-8: Calls the endpoint via Network.Wai.Test, asserts:
   1. Valid Pub/Sub push → HTTP 200.
   2. Duplicate identifier re-sent → HTTP 200 (idempotent).
   3. Invalid CloudEvent (missing identifier field) → HTTP 200 (schema_invalid).

 Requires FIRESTORE_EMULATOR_HOST.  If not set, all cases are pending.

 PubSub publish is best-effort; the test publisher points to a non-existent
 host, so publish silently fails without affecting persistence assertions.
-}
module Presentation.IntegrationSpec (spec) where

import App.Bootstrap (HttpServiceOptions (..), mkApplication)
import Config.Env (CommonRuntimeEnv (..))
import Data.Aeson (Value, encode, object, (.=))
import Data.Base64.Types (extractBase64)
import Data.ByteString.Base64 (encodeBase64)
import Data.ByteString.Lazy qualified as ByteStringLazy
import Data.Text (Text)
import Data.Text qualified as Text
import Data.ULID (ULID, ulidFromInteger)
import Messaging.PubSub (PubSubPublisher (..))
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Network.HTTP.Types (methodPost)
import Network.Wai (defaultRequest)
import Network.Wai.Internal (Request (..))
import Network.Wai.Test (
  SRequest (..),
  assertBody,
  assertStatus,
  runSession,
  srequest,
 )
import Observability.Logging (initLogger)
import Persistence.Firestore (FirestoreContext (..))
import Presentation.Api (auditLogApiProxy, auditLogServer)
import Presentation.AppM (AppEnv (..))
import System.Environment (lookupEnv)
import Test.Hspec (Spec, describe, it, pendingWith)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

integrationSourceULIDFirst :: Text
integrationSourceULIDFirst = Text.pack (show (mkULID 3001))

integrationSourceULIDSecond :: Text
integrationSourceULIDSecond = Text.pack (show (mkULID 3002))

integrationSourceULIDThird :: Text
integrationSourceULIDThird = Text.pack (show (mkULID 3003))

-- | Encode a CloudEvent-like JSON Value as a base64'd Pub/Sub push body.
buildPubSubBody :: Value -> ByteStringLazy.ByteString
buildPubSubBody cloudEventValue =
  let rawBytes = ByteStringLazy.toStrict (encode cloudEventValue)
      base64Data = extractBase64 (encodeBase64 rawBytes)
   in encode
        ( object
            [ "message"
                .= object
                  [ "messageId" .= ("integration-msg" :: Text)
                  , "publishTime" .= ("2025-06-01T00:00:00Z" :: Text)
                  , "data" .= base64Data
                  ]
            ]
        )

validCloudEventWith :: Text -> Value
validCloudEventWith ulidText =
  object
    [ "identifier" .= ulidText
    , "eventType" .= ("orders.executed" :: Text)
    , "occurredAt" .= ("2025-06-01T00:00:00Z" :: Text)
    , "trace" .= ("01BX5ZZKBKACTAV9WEVGEMMVS0" :: Text)
    , "schemaVersion" .= ("1.0" :: Text)
    , "payload" .= object []
    ]

invalidCloudEventMissingIdentifier :: Value
invalidCloudEventMissingIdentifier =
  object
    [ "eventType" .= ("orders.executed" :: Text)
    , "occurredAt" .= ("2025-06-01T00:00:00Z" :: Text)
    , "trace" .= ("01BX5ZZKBKACTAV9WEVGEMMVS0" :: Text)
    , "schemaVersion" .= ("1.0" :: Text)
    , "payload" .= object []
    ]

-- ---------------------------------------------------------------------------
-- Test AppEnv builder
-- ---------------------------------------------------------------------------

makeIntegrationAppEnv :: IO AppEnv
makeIntegrationAppEnv = do
  httpManager <- newManager defaultManagerSettings
  let runtimeEnv =
        CommonRuntimeEnv
          { port = 8080
          , gcpProjectId = "test-project"
          , serviceName = "audit-log"
          , serviceVersion = "test"
          , revision = Nothing
          , logLevel = "info"
          }
  logEnvironment <- initLogger runtimeEnv
  let firestoreCtx =
        FirestoreContext
          { projectId = "test-project"
          , databaseId = "(default)"
          }
      publisher =
        PubSubPublisher
          { manager = httpManager
          , projectId = "test-project"
          , baseURL = "http://localhost:19999/"
          , accessToken = pure "test-token"
          }
  pure
    AppEnv
      { firestoreContext = firestoreCtx
      , logEnv = logEnvironment
      , pubSubPublisher = publisher
      , auditTopicName = "audit-recorded"
      , serviceName = "audit-log"
      }

-- ---------------------------------------------------------------------------
-- Wai request builder
-- ---------------------------------------------------------------------------

makePubSubRequest :: ByteStringLazy.ByteString -> SRequest
makePubSubRequest body =
  SRequest
    { simpleRequest =
        defaultRequest
          { requestMethod = methodPost
          , pathInfo = ["pubsub", "events"]
          , requestHeaders = [("Content-Type", "application/json")]
          }
    , simpleRequestBody = body
    }

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "Integration: POST /pubsub/events" $ do
    it "valid event → HTTP 200 (requires FIRESTORE_EMULATOR_HOST)" $ do
      maybeEmulatorHost <- lookupEnv "FIRESTORE_EMULATOR_HOST"
      case maybeEmulatorHost of
        Nothing ->
          pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping integration tests"
        Just _ -> do
          appEnv <- makeIntegrationAppEnv
          application <-
            mkApplication
              HttpServiceOptions
                { serviceName = "audit-log"
                , serviceVersion = "test"
                , metricsPath = Nothing
                , middlewareStack = []
                , beforeRun = pure ()
                }
              auditLogApiProxy
              (auditLogServer appEnv)
          let body = buildPubSubBody (validCloudEventWith integrationSourceULIDFirst)
          runSession
            ( do
                response <- srequest (makePubSubRequest body)
                assertStatus 200 response
            )
            application

    it "duplicate identifier → HTTP 200 idempotent (requires FIRESTORE_EMULATOR_HOST)" $ do
      maybeEmulatorHost <- lookupEnv "FIRESTORE_EMULATOR_HOST"
      case maybeEmulatorHost of
        Nothing ->
          pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping integration tests"
        Just _ -> do
          appEnv <- makeIntegrationAppEnv
          application <-
            mkApplication
              HttpServiceOptions
                { serviceName = "audit-log"
                , serviceVersion = "test"
                , metricsPath = Nothing
                , middlewareStack = []
                , beforeRun = pure ()
                }
              auditLogApiProxy
              (auditLogServer appEnv)
          let body = buildPubSubBody (validCloudEventWith integrationSourceULIDSecond)
          runSession
            ( do
                -- First request: Recorded
                responseFirst <- srequest (makePubSubRequest body)
                assertStatus 200 responseFirst
                assertBody (encode (object ["result" .= ("recorded" :: Text)])) responseFirst
                -- Second request with same source event identifier: must be
                -- deduplicated. RULE-AU-002 — proves the idempotency key is the
                -- source event identifier (not a fresh per-request ULID).
                responseSecond <- srequest (makePubSubRequest body)
                assertStatus 200 responseSecond
                assertBody (encode (object ["result" .= ("duplicate" :: Text)])) responseSecond
            )
            application

    it "invalid CloudEvent (missing identifier) → HTTP 200 schema_invalid (requires FIRESTORE_EMULATOR_HOST)" $ do
      maybeEmulatorHost <- lookupEnv "FIRESTORE_EMULATOR_HOST"
      case maybeEmulatorHost of
        Nothing ->
          pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping integration tests"
        Just _ -> do
          appEnv <- makeIntegrationAppEnv
          application <-
            mkApplication
              HttpServiceOptions
                { serviceName = "audit-log"
                , serviceVersion = "test"
                , metricsPath = Nothing
                , middlewareStack = []
                , beforeRun = pure ()
                }
              auditLogApiProxy
              (auditLogServer appEnv)
          let body = buildPubSubBody invalidCloudEventMissingIdentifier
          runSession
            ( do
                response <- srequest (makePubSubRequest body)
                assertStatus 200 response
            )
            application
