{-# OPTIONS_GHC -fno-hpc #-}

{- | Tests for 'Presentation.PubSubHandler'.

 Must-20: All test cases use 'processPubSubPushWith' with an in-memory stub
 usecase runner — no real GCP calls (no Firestore, Pub/Sub, or SkillExecutor).

 Must-21: The 7 required test cases are:
   1. insight.collected success
   2. insight.collected duplicate (idempotency)
   3. hypothesis.retest.requested success
   4. schema invalid (bad JSON body)
   5. non-retryable error (ResourceNotFound → 200)
   6. retryable error (DependencyTimeout → 500)
   7. unknown event type → 200
-}
module Presentation.PubSubHandlerSpec (spec) where

import Config.Env (CommonRuntimeEnv (..))
import Data.Aeson (Value, encode, object, (.=))
import Data.Base64.Types (extractBase64)
import Data.ByteString.Base64 (encodeBase64)
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Text (Text)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Observability.Logging (LogEnv, initLogger)
import Presentation.PubSubHandler (
  PubSubPushResult (..),
  processPubSubPushWith,
  pubSubPushResultToStatus,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- ULID fixtures
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case readMaybe "01ARZ3NDEKTSV4RRFFQ69G5FAV" of
  Just ulid -> ulid
  Nothing -> error "invalid test ULID"

testTraceUlid :: ULID
testTraceUlid = case readMaybe "01BX5ZZKBKACTAV9WEVGEMMVRE" of
  Just ulid -> ulid
  Nothing -> error "invalid test trace ULID"

-- ---------------------------------------------------------------------------
-- Pub/Sub body builders
-- ---------------------------------------------------------------------------

-- | Build a Pub/Sub push body wrapping a CloudEvents-shaped JSON value.
buildPubSubBody :: Value -> ByteString.Lazy.ByteString
buildPubSubBody cloudEventValue =
  let rawBytes = ByteString.Lazy.toStrict (encode cloudEventValue)
      base64Data = extractBase64 (encodeBase64 rawBytes)
   in encode
        ( object
            [ "message"
                .= object
                  [ "messageId" .= ("test-msg-id" :: Text)
                  , "publishTime" .= ("2026-01-15T00:00:00Z" :: Text)
                  , "data" .= base64Data
                  ]
            ]
        )

-- | Fixed occurrence timestamp for payloads.
testOccurredAt :: Text
testOccurredAt = "2026-01-15T00:00:00Z"

-- | Build an insight.collected Pub/Sub body.
insightCollectedBody :: ByteString.Lazy.ByteString
insightCollectedBody =
  buildPubSubBody $
    object
      [ "identifier" .= show testUlid
      , "eventType" .= ("insight.collected" :: Text)
      , "occurredAt" .= testOccurredAt
      , "trace" .= show testTraceUlid
      , "schemaVersion" .= ("1.0.0" :: Text)
      , "payload"
          .= object
            [ "insightIdentifier" .= ("insight-001" :: Text)
            , "dispatchReference" .= ("dispatch-001" :: Text)
            , "trace" .= show testTraceUlid
            , "occurredAt" .= testOccurredAt
            ]
      ]

-- | Build a hypothesis.retest.requested Pub/Sub body.
retestRequestedBody :: ByteString.Lazy.ByteString
retestRequestedBody =
  buildPubSubBody $
    object
      [ "identifier" .= show testUlid
      , "eventType" .= ("hypothesis.retest.requested" :: Text)
      , "occurredAt" .= testOccurredAt
      , "trace" .= show testTraceUlid
      , "schemaVersion" .= ("1.0.0" :: Text)
      , "payload"
          .= object
            [ "retestIdentifier" .= ("retest-001" :: Text)
            , "dispatchReference" .= ("dispatch-001" :: Text)
            , "trace" .= show testTraceUlid
            , "occurredAt" .= testOccurredAt
            ]
      ]

-- | Build an unknown event type Pub/Sub body.
unknownEventBody :: ByteString.Lazy.ByteString
unknownEventBody =
  buildPubSubBody $
    object
      [ "identifier" .= show testUlid
      , "eventType" .= ("unknown.event" :: Text)
      , "occurredAt" .= testOccurredAt
      , "trace" .= show testTraceUlid
      , "schemaVersion" .= ("1.0.0" :: Text)
      , "payload" .= object []
      ]

-- | Invalid JSON body (cannot be parsed at all).
invalidJsonBody :: ByteString.Lazy.ByteString
invalidJsonBody = "not-valid-json{{{"

-- ---------------------------------------------------------------------------
-- Stub usecase runners (Must-20: no real GCP calls)
-- ---------------------------------------------------------------------------

-- | Stub that always returns success.
successRunner ::
  a ->
  b ->
  c ->
  d ->
  e ->
  IO (Either DomainError ())
successRunner _ _ _ _ _ = pure (Right ())

-- | Stub that returns AlreadyProcessed (idempotency duplicate).
duplicateRunner ::
  a ->
  b ->
  c ->
  d ->
  e ->
  IO (Either DomainError ())
duplicateRunner _ _ _ _ _ =
  pure (Left (AlreadyProcessed IdempotencyDuplicateEvent))

-- | Stub that returns InvariantViolation with ResourceNotFound (non-retryable).
resourceNotFoundRunner ::
  a ->
  b ->
  c ->
  d ->
  e ->
  IO (Either DomainError ())
resourceNotFoundRunner _ _ _ _ _ =
  pure (Left (InvariantViolation "HypothesisOrchestration" "Skill not found" ResourceNotFound))

-- | Stub that returns InvariantViolation with DependencyTimeout (retryable).
dependencyTimeoutRunner ::
  a ->
  b ->
  c ->
  d ->
  e ->
  IO (Either DomainError ())
dependencyTimeoutRunner _ _ _ _ _ =
  pure (Left (InvariantViolation "SkillExecutor" "timeout" DependencyTimeout))

-- ---------------------------------------------------------------------------
-- Spec (Must-21: 7 test cases)
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "Presentation.PubSubHandler" $ do
    describe "Must-21: processPubSubPushWith — core test cases" $ do
      it "Case 1: insight.collected success → PubSubPushOrchestrationSucceeded" $ do
        logEnvironment <- makeTestLogEnv
        result <- processPubSubPushWith logEnvironment successRunner insightCollectedBody
        result `shouldBe` PubSubPushOrchestrationSucceeded

      it "Case 2: insight.collected duplicate → PubSubPushOrchestrationDuplicate" $ do
        logEnvironment <- makeTestLogEnv
        result <- processPubSubPushWith logEnvironment duplicateRunner insightCollectedBody
        result `shouldBe` PubSubPushOrchestrationDuplicate

      it "Case 3: hypothesis.retest.requested success → PubSubPushOrchestrationSucceeded" $ do
        logEnvironment <- makeTestLogEnv
        result <- processPubSubPushWith logEnvironment successRunner retestRequestedBody
        result `shouldBe` PubSubPushOrchestrationSucceeded

      it "Case 4: schema invalid (bad JSON) → PubSubPushSchemaInvalid" $ do
        logEnvironment <- makeTestLogEnv
        result <- processPubSubPushWith logEnvironment successRunner invalidJsonBody
        result `shouldSatisfy` isSchemaInvalid

      it "Case 5: non-retryable error (ResourceNotFound) → PubSubPushSchemaInvalid (200)" $ do
        logEnvironment <- makeTestLogEnv
        result <- processPubSubPushWith logEnvironment resourceNotFoundRunner insightCollectedBody
        result `shouldSatisfy` isSchemaInvalid

      it "Case 6: retryable error (DependencyTimeout) → PubSubPushOrchestrationFailed (500)" $ do
        logEnvironment <- makeTestLogEnv
        result <- processPubSubPushWith logEnvironment dependencyTimeoutRunner insightCollectedBody
        result `shouldSatisfy` isOrchestrationFailed

      it "Case 7: unknown eventType → PubSubPushUnknownEventType (200)" $ do
        logEnvironment <- makeTestLogEnv
        result <- processPubSubPushWith logEnvironment successRunner unknownEventBody
        result `shouldSatisfy` isUnknownEventType

    describe "Must-13: pubSubPushResultToStatus HTTP mapping" $ do
      it "PubSubPushOrchestrationSucceeded maps to Right (HTTP 200)" $ do
        pubSubPushResultToStatus PubSubPushOrchestrationSucceeded
          `shouldBe` Right PubSubPushOrchestrationSucceeded

      it "PubSubPushOrchestrationDuplicate maps to Right (HTTP 200)" $ do
        pubSubPushResultToStatus PubSubPushOrchestrationDuplicate
          `shouldBe` Right PubSubPushOrchestrationDuplicate

      it "PubSubPushSchemaInvalid maps to Right (HTTP 200 — permanent failure)" $ do
        pubSubPushResultToStatus (PubSubPushSchemaInvalid "test")
          `shouldBe` Right (PubSubPushSchemaInvalid "test")

      it "PubSubPushUnknownEventType maps to Right (HTTP 200 — ack)" $ do
        pubSubPushResultToStatus (PubSubPushUnknownEventType "unknown.event")
          `shouldBe` Right (PubSubPushUnknownEventType "unknown.event")

      it "PubSubPushOrchestrationFailed maps to Left (HTTP 500 — transient, re-deliver)" $ do
        pubSubPushResultToStatus (PubSubPushOrchestrationFailed "transient")
          `shouldSatisfy` isLeft

-- ---------------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------------

makeTestLogEnv :: IO LogEnv
makeTestLogEnv = do
  let runtimeEnv =
        CommonRuntimeEnv
          { port = 8080
          , gcpProjectId = "test-project"
          , serviceName = "agent-orchestrator"
          , serviceVersion = "test"
          , revision = Nothing
          , logLevel = "info"
          }
  initLogger runtimeEnv

isSchemaInvalid :: PubSubPushResult -> Bool
isSchemaInvalid (PubSubPushSchemaInvalid _) = True
isSchemaInvalid _ = False

isOrchestrationFailed :: PubSubPushResult -> Bool
isOrchestrationFailed (PubSubPushOrchestrationFailed _) = True
isOrchestrationFailed _ = False

isUnknownEventType :: PubSubPushResult -> Bool
isUnknownEventType (PubSubPushUnknownEventType _) = True
isUnknownEventType _ = False

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False
