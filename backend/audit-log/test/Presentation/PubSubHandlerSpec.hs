{-# OPTIONS_GHC -fno-hpc #-}

{- | Unit tests for 'Presentation.PubSubHandler'.

 Must-3: Verifies that decode errors (invalid ULID identifier, invalid
 occurredAt without timezone) map to HTTP 200 (SchemaInvalid).

 These tests do not require Firestore; they use a test 'AppEnv' with a
 no-op Firestore context (calls would fail at network level but the decode
 path returns before reaching Firestore).
-}
module Presentation.PubSubHandlerSpec (spec) where

import Config.Env (CommonRuntimeEnv (..))
import Data.Aeson (Value (..), encode, object, (.=))
import Data.Base64.Types (extractBase64)
import Data.ByteString.Base64 (encodeBase64)
import Data.ByteString.Lazy qualified as ByteStringLazy
import Data.Text qualified as Text
import Messaging.PubSub (PubSubPublisher (..))
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Observability.Logging (initLogger)
import Persistence.Firestore (FirestoreContext (..))
import Presentation.AppM (AppEnv (..))
import Presentation.PubSubHandler (
  PubSubPushResult (..),
  processPubSubPush,
  pubSubPushResultToStatus,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

makeMinimalAppEnv :: IO AppEnv
makeMinimalAppEnv = do
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

-- | Build a Pub/Sub push body from a CloudEvent-like JSON value.
buildPubSubBody :: Value -> ByteStringLazy.ByteString
buildPubSubBody cloudEventValue =
  let rawBytes = ByteStringLazy.toStrict (encode cloudEventValue)
      base64Data = extractBase64 (encodeBase64 rawBytes)
   in encode
        ( object
            [ "message"
                .= object
                  [ "messageId" .= ("test-msg-id" :: Text.Text)
                  , "publishTime" .= ("2025-06-01T00:00:00Z" :: Text.Text)
                  , "data" .= base64Data
                  ]
            ]
        )

cloudEventWithInvalidIdentifier :: Value
cloudEventWithInvalidIdentifier =
  object
    [ "identifier" .= ("not-a-valid-ulid-xxx" :: Text.Text)
    , "eventType" .= ("orders.executed" :: Text.Text)
    , "occurredAt" .= ("2025-06-01T00:00:00Z" :: Text.Text)
    , "trace" .= ("01BX5ZZKBKACTAV9WEVGEMMVS0" :: Text.Text)
    , "schemaVersion" .= ("1.0" :: Text.Text)
    , "payload" .= object []
    ]

cloudEventWithInvalidOccurredAt :: Value
cloudEventWithInvalidOccurredAt =
  object
    [ "identifier" .= ("01ARZ3NDEKTSV4RRFFQ69G5FAV" :: Text.Text)
    , "eventType" .= ("orders.executed" :: Text.Text)
    , "occurredAt" .= ("2025-06-01T00:00:00" :: Text.Text)
    , "trace" .= ("01BX5ZZKBKACTAV9WEVGEMMVS0" :: Text.Text)
    , "schemaVersion" .= ("1.0" :: Text.Text)
    , "payload" .= object []
    ]

invalidJsonBody :: ByteStringLazy.ByteString
invalidJsonBody = "not-valid-json{{{}"

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "Presentation.PubSubHandler" $ do
    describe "Must-3: decode errors return PubSubPushSchemaInvalid" $ do
      it "invalid JSON body returns SchemaInvalid" $ do
        appEnv <- makeMinimalAppEnv
        result <- processPubSubPush appEnv invalidJsonBody
        result `shouldSatisfy` isSchemaInvalid

      it "invalid identifier (bad ULID) returns SchemaInvalid" $ do
        appEnv <- makeMinimalAppEnv
        let body = buildPubSubBody cloudEventWithInvalidIdentifier
        result <- processPubSubPush appEnv body
        result `shouldSatisfy` isSchemaInvalid

      it "invalid occurredAt (no timezone marker) returns SchemaInvalid" $ do
        appEnv <- makeMinimalAppEnv
        let body = buildPubSubBody cloudEventWithInvalidOccurredAt
        result <- processPubSubPush appEnv body
        result `shouldSatisfy` isSchemaInvalid

    describe "pubSubPushResultToStatus HTTP mapping (RULE-AU-007)" $ do
      it "Recorded maps to Right (no 5xx)" $ do
        pubSubPushResultToStatus PubSubPushRecorded `shouldBe` Right PubSubPushRecorded

      it "Duplicate maps to Right (no 5xx)" $ do
        pubSubPushResultToStatus PubSubPushDuplicate `shouldBe` Right PubSubPushDuplicate

      it "SchemaInvalid maps to Right (no 5xx — permanent failure, do not re-deliver)" $ do
        pubSubPushResultToStatus (PubSubPushSchemaInvalid "test") `shouldBe` Right (PubSubPushSchemaInvalid "test")

      it "WriteFailed maps to Left (5xx — transient, re-deliver)" $ do
        let result = pubSubPushResultToStatus (PubSubPushWriteFailed "transient")
        result `shouldSatisfy` isLeft

      it "DomainError maps to Left (5xx — transient, re-deliver)" $ do
        let result = pubSubPushResultToStatus (PubSubPushDomainError "domain")
        result `shouldSatisfy` isLeft

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

isSchemaInvalid :: PubSubPushResult -> Bool
isSchemaInvalid (PubSubPushSchemaInvalid _) = True
isSchemaInvalid _ = False

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False
