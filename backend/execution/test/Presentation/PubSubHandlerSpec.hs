{-# OPTIONS_GHC -fno-hpc #-}

{- | Unit tests for 'Presentation.PubSubHandler'.

 Tests call 'processOrdersApprovedWith' (IO function) with injectable
 usecase runner, observing real entrypoint behaviour without hitting
 Firestore or Pub/Sub.

 TST-PRES-001: Valid CloudEvents envelope → PubSubPushExecutionSucceeded
 TST-PRES-002: Invalid JSON body → PubSubPushSchemaInvalid
 TST-PRES-003: pubSubPushResultToStatus covers all 5 variants
 TST-PRES-004: buildLogContext produces service="execution", trace /= Nothing
 TST-PRES-005: ExecuteOrderDuplicate maps to PubSubPushExecutionDuplicate
-}
module Presentation.PubSubHandlerSpec (spec) where

import Config.Env (CommonRuntimeEnv (..))
import Data.Aeson (Value, encode, object, (.=))
import Data.Base64.Types (extractBase64)
import Data.ByteString.Base64 (encodeBase64)
import Data.ByteString.Lazy qualified as ByteStringLazy
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.ULID (ULID, ulidFromInteger)
import Observability.Logging (LogContext (..), LogEnv, initLogger)
import Presentation.PubSubHandler (
  PubSubPushResult (..),
  buildLogContext,
  processOrdersApprovedWith,
  pubSubPushResultToStatus,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.ExecuteOrder (ExecuteOrderResult (..))

spec :: Spec
spec = do
  describe "PubSubHandlerSpec" $ do
    -- TST-PRES-001: Valid CloudEvents envelope → PubSubPushExecutionSucceeded
    describe "TST-PRES-001: valid orders.approved CloudEvents body → succeeded" $ do
      it "returns PubSubPushExecutionSucceeded for a valid approved order event" $ do
        logEnvironment <- buildTestLogEnv
        let body = buildValidOrdersApprovedBody testIdentifierUlid testTraceUlid "7203.T" "BUY" 100
            fakeRunner _ _ = pure ExecuteOrderSucceeded
        result <- processOrdersApprovedWith logEnvironment fakeRunner body
        result `shouldBe` PubSubPushExecutionSucceeded

    -- TST-PRES-002: Invalid JSON body → PubSubPushSchemaInvalid
    describe "TST-PRES-002: invalid JSON body → schema invalid (HTTP 200)" $ do
      it "returns PubSubPushSchemaInvalid for malformed body" $ do
        logEnvironment <- buildTestLogEnv
        let body = ByteStringLazy.fromStrict (TextEncoding.encodeUtf8 "not-json")
            fakeRunner _ _ = pure ExecuteOrderSucceeded
        result <- processOrdersApprovedWith logEnvironment fakeRunner body
        case result of
          PubSubPushSchemaInvalid _ -> pure ()
          other -> fail ("expected PubSubPushSchemaInvalid, got: " <> show other)

    -- TST-PRES-003: pubSubPushResultToStatus maps variants correctly
    describe "TST-PRES-003: pubSubPushResultToStatus HTTP status mapping" $ do
      it "PubSubPushExecutionSucceeded → Right (HTTP 200)" $
        pubSubPushResultToStatus PubSubPushExecutionSucceeded
          `shouldBe` Right PubSubPushExecutionSucceeded

      it "PubSubPushExecutionDuplicate → Right (HTTP 200)" $
        pubSubPushResultToStatus PubSubPushExecutionDuplicate
          `shouldBe` Right PubSubPushExecutionDuplicate

      it "PubSubPushSchemaInvalid → Right (HTTP 200, no re-delivery)" $
        pubSubPushResultToStatus (PubSubPushSchemaInvalid "bad schema")
          `shouldBe` Right (PubSubPushSchemaInvalid "bad schema")

      it "PubSubPushExecutionRetryable → Left err500 (Pub/Sub re-delivery)" $
        pubSubPushResultToStatus (PubSubPushExecutionRetryable "timeout")
          `shouldSatisfy` \case
            Left _ -> True
            Right _ -> False

      it "PubSubPushExecutionFailed → Right (HTTP 200, permanent failure)" $
        pubSubPushResultToStatus (PubSubPushExecutionFailed "EXECUTION_BROKER_REJECTED")
          `shouldBe` Right (PubSubPushExecutionFailed "EXECUTION_BROKER_REJECTED")

    -- TST-PRES-004: buildLogContext service field
    describe "TST-PRES-004: buildLogContext produces correct service field" $ do
      it "service = execution and trace/identifier preserved" $ do
        let LogContext{service = serviceField, trace = traceField, identifier = identifierField} =
              buildLogContext "orders.approved" (Just "trace-1") (Just "id-1") Nothing Nothing
        serviceField `shouldBe` "execution"
        isJust traceField `shouldBe` True
        isJust identifierField `shouldBe` True

    -- TST-PRES-005: duplicate result mapping
    describe "TST-PRES-005: ExecuteOrderDuplicate maps to PubSubPushExecutionDuplicate" $ do
      it "returns PubSubPushExecutionDuplicate when usecase returns ExecuteOrderDuplicate" $ do
        logEnvironment <- buildTestLogEnv
        let body = buildValidOrdersApprovedBody testIdentifierUlid testTraceUlid "7203.T" "BUY" 100
            fakeRunner _ _ = pure ExecuteOrderDuplicate
        result <- processOrdersApprovedWith logEnvironment fakeRunner body
        result `shouldBe` PubSubPushExecutionDuplicate

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testIdentifierUlid :: ULID
testIdentifierUlid = case ulidFromInteger 1 of
  Right ulid -> ulid
  Left _ -> error "test identifier ulid"

testTraceUlid :: ULID
testTraceUlid = case ulidFromInteger 2 of
  Right ulid -> ulid
  Left _ -> error "test trace ulid"

buildTestLogEnv :: IO LogEnv
buildTestLogEnv = do
  let runtimeEnv =
        CommonRuntimeEnv
          { port = 8080
          , gcpProjectId = "test-project"
          , serviceName = "execution"
          , serviceVersion = "test"
          , revision = Nothing
          , logLevel = "info"
          }
  initLogger runtimeEnv

{- | Build a valid Pub/Sub push body for 'orders.approved' with symbol/side/qty in payload.

 Encodes a CloudEvent envelope with a base64-encoded message.data containing
 the JSON CloudEvent body.
-}
buildValidOrdersApprovedBody ::
  ULID ->
  ULID ->
  Text ->
  Text ->
  Int ->
  ByteStringLazy.ByteString
buildValidOrdersApprovedBody identifierUlid traceUlid symbolValue sideValue qtyValue =
  let cloudEventPayload :: Value
      cloudEventPayload =
        object
          [ "identifier" .= Text.pack (show identifierUlid)
          , "decision" .= ("approved" :: Text)
          , "symbol" .= symbolValue
          , "side" .= sideValue
          , "qty" .= qtyValue
          ]
      cloudEventBody :: Value
      cloudEventBody =
        object
          [ "identifier" .= Text.pack (show identifierUlid)
          , "eventType" .= ("orders.approved" :: Text)
          , "occurredAt" .= ("2026-01-15T09:00:00Z" :: Text)
          , "trace" .= Text.pack (show traceUlid)
          , "schemaVersion" .= ("1.0.0" :: Text)
          , "payload" .= cloudEventPayload
          ]
      cloudEventBytes = ByteStringLazy.toStrict (encode cloudEventBody)
      base64Data = extractBase64 (encodeBase64 cloudEventBytes)
      pubSubEnvelope :: Value
      pubSubEnvelope =
        object
          [ "message"
              .= object
                [ "data" .= base64Data
                , "messageId" .= ("msg-001" :: Text)
                , "publishTime" .= ("2026-01-15T09:00:00Z" :: Text)
                ]
          , "subscription" .= ("projects/test-project/subscriptions/orders-approved" :: Text)
          ]
   in encode pubSubEnvelope
