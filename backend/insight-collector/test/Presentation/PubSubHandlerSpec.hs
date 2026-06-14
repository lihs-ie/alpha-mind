{-# OPTIONS_GHC -fno-hpc #-}

{- | Integration tests for 'Presentation.PubSubHandler'.

 MUST-15: Tests call 'processPubSubPushWith' (IO function with injectable runner)
 and 'processPubSubPush' directly, observing real entrypoint behaviour:
   1. Valid CloudEvents envelope + success runner → PubSubPushCollectionSucceeded
   2. Invalid JSON body → PubSubPushSchemaInvalid (HTTP 200 ack)
   3. Valid envelope + retryable failure runner → PubSubPushWriteFailed (HTTP 500)
   4. Valid envelope + non-retryable failure runner → PubSubPushSchemaInvalid (HTTP 200)
   5. buildLogContext service/trace/identifier fields

 Test doubles (FakeAppM) live in this test file only; no mock enters src/.
-}
module Presentation.PubSubHandlerSpec (spec) where

import Config.Env (CommonRuntimeEnv (..))
import Control.Monad.IO.Class (MonadIO (liftIO))
import Data.Aeson (Value, encode, object, (.=))
import Data.Base64.Types (extractBase64)
import Data.ByteString.Base64 (encodeBase64)
import Data.ByteString.Lazy qualified as ByteStringLazy
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime (..), getCurrentTime)
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (
  InsightArtifactRepository (..),
  InsightCollection,
  InsightCollectionIdentifier (..),
  InsightCollectionRepository (..),
  InsightRecord,
  InsightRecordRepository (..),
  RequestedBy (..),
  SourceConfig (..),
  SourcePolicyRepository (..),
  SourcePolicySnapshot (..),
  SourceType (..),
  XConfig (..),
 )
import Domain.InsightCollection.ExternalSourcePort (ExternalSourcePort (..))
import Domain.InsightCollection.InsightDispatch (
  InsightDispatch,
  InsightDispatchRepository (..),
 )
import Domain.InsightCollection.ReasonCode (ReasonCode (..))
import Messaging.CloudEvent (CloudEvent (..))
import Observability.Logging (LogContext (..), LogEnv, initLogger)
import Presentation.PubSubHandler (
  PubSubPushResult (..),
  buildLogContext,
  cloudEventToRawInsightEvent,
  processPubSubPushWith,
  pubSubPushResultToStatus,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.CollectInsights (
  CollectInsightsResult (..),
  InsightCollectionEventPublisher (..),
  RawInsightEvent (..),
  collectInsights,
 )
import UseCase.RecordInsightAudit (InsightAuditEntry (..), InsightAuditPort (..))

-- ---------------------------------------------------------------------------
-- Fake monad for tests (test-only — lives in test/ only)
-- ---------------------------------------------------------------------------

data FakeState = FakeState
  { collectionStore :: Map.Map Text InsightCollection
  , dispatchStore :: Map.Map Text InsightDispatch
  , auditEntries :: [(InsightCollectionIdentifier, Trace, InsightAuditEntry)]
  }

emptyFakeState :: FakeState
emptyFakeState =
  FakeState
    { collectionStore = Map.empty
    , dispatchStore = Map.empty
    , auditEntries = []
    }

newtype FakeAppM a = FakeAppM {runFakeAppM :: IORef FakeState -> IO a}

instance Functor FakeAppM where
  fmap f (FakeAppM g) = FakeAppM $ \ref -> fmap f (g ref)

instance Applicative FakeAppM where
  pure a = FakeAppM $ \_ -> pure a
  FakeAppM f <*> FakeAppM a = FakeAppM $ \ref -> f ref <*> a ref

instance Monad FakeAppM where
  FakeAppM a >>= f = FakeAppM $ \ref -> do
    value <- a ref
    runFakeAppM (f value) ref

instance MonadIO FakeAppM where
  liftIO action = FakeAppM (const action)

-- Port instances for FakeAppM

instance InsightDispatchRepository FakeAppM where
  findDispatch collectionIdentifier = FakeAppM $ \ref -> do
    state <- readIORef ref
    pure $ Map.lookup (showText collectionIdentifier.value) state.dispatchStore
  persistDispatch dispatch = FakeAppM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { dispatchStore =
            Map.insert (showText dispatch.identifier.value) dispatch state.dispatchStore
        }
  terminateDispatch' _ = pure ()

instance InsightCollectionRepository FakeAppM where
  findCollection collectionIdentifier = FakeAppM $ \ref -> do
    state <- readIORef ref
    pure $ Map.lookup (showText collectionIdentifier.value) state.collectionStore
  findByStatus _ = pure []
  searchCollections _ = pure []
  persistCollection collection = FakeAppM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { collectionStore =
            Map.insert (showText collection.identifier.value) collection state.collectionStore
        }
  terminateCollectionRecord _ = pure ()

-- Return one approved policy so the use case can succeed with 0 records
fakePolicySnapshot :: SourcePolicySnapshot
fakePolicySnapshot =
  SourcePolicySnapshot
    { sourceType = X
    , enabled = True
    , termsVersion = "1.0"
    , redistributionAllowed = True
    , dailyQuota = Nothing
    , sourceConfig = XSourceConfig (XConfig{bearerTokenSecretName = "test-token-secret"})
    }

instance SourcePolicyRepository FakeAppM where
  searchPolicies _ = pure [fakePolicySnapshot]
  findBySourceType sourceTypeValue
    | sourceTypeValue == X = pure (Just fakePolicySnapshot)
    | otherwise = pure Nothing

instance InsightRecordRepository FakeAppM where
  persistRecord _ = pure ()
  searchRecords _ _ = pure []
  findByTargetDate _ = pure []

instance InsightArtifactRepository FakeAppM where
  persistArtifact _ = pure ()
  findArtifact _ = pure Nothing
  terminateArtifact _ = pure ()

instance ExternalSourcePort FakeAppM where
  fetchInsights _ _ = pure (Right [])

instance InsightCollectionEventPublisher FakeAppM where
  publishInsightCollected _ _ _ = pure ()
  publishInsightCollectFailed _ _ _ _ = pure ()

instance InsightAuditPort FakeAppM where
  writeInsightAudit collectionIdentifier traceValue entry = FakeAppM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { auditEntries = (collectionIdentifier, traceValue, entry) : state.auditEntries
        }

-- ---------------------------------------------------------------------------
-- Pub/Sub body builders
-- ---------------------------------------------------------------------------

buildPubSubBody :: Value -> ByteStringLazy.ByteString
buildPubSubBody cloudEventValue =
  let rawBytes = ByteStringLazy.toStrict (encode cloudEventValue)
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

invalidJsonBody :: ByteStringLazy.ByteString
invalidJsonBody = "not-valid-json{{{"

validUlidText1 :: Text
validUlidText1 = "01ARZ3NDEKTSV4RRFFQ69G5FAV"

validCloudEventValue :: Value
validCloudEventValue =
  object
    [ "identifier" .= validUlidText1
    , "eventType" .= ("insight.collect.requested" :: Text)
    , "occurredAt" .= ("2026-01-15T00:00:00Z" :: Text)
    , "trace" .= validUlidText1
    , "schemaVersion" .= ("1.0.0" :: Text)
    , "payload"
        .= object
          [ "targetDate" .= ("2026-01-15" :: Text)
          , "requestedBy" .= ("scheduler" :: Text)
          , "requestedSourceTypes" .= (["X"] :: [Text])
          ]
    ]

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

mkUlid :: Integer -> ULID
mkUlid n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

showText :: (Show a) => a -> Text
showText = Text.pack . show

isSchemaInvalid :: PubSubPushResult -> Bool
isSchemaInvalid (PubSubPushSchemaInvalid _) = True
isSchemaInvalid _ = False

isWriteFailed :: PubSubPushResult -> Bool
isWriteFailed (PubSubPushWriteFailed _) = True
isWriteFailed _ = False

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False

makeTestLogEnv :: IO LogEnv
makeTestLogEnv = do
  let runtimeEnv =
        CommonRuntimeEnv
          { port = 8080
          , gcpProjectId = "test-project"
          , serviceName = "insight-collector"
          , serviceVersion = "test"
          , revision = Nothing
          , logLevel = "info"
          }
  initLogger runtimeEnv

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "Presentation.PubSubHandler" $ do
    describe "MUST-15: processPubSubPushWith integration" $ do
      it "Case 1: valid CloudEvents envelope + success runner → PubSubPushCollectionSucceeded" $ do
        logEnvironment <- makeTestLogEnv
        stateRef <- newIORef emptyFakeState
        let body = buildPubSubBody validCloudEventValue
        result <-
          processPubSubPushWith
            logEnvironment
            ( \currentTime collectionIdentifier rawInsightEvent ->
                runFakeAppM
                  (collectInsights currentTime collectionIdentifier rawInsightEvent)
                  stateRef
            )
            body
        result `shouldBe` PubSubPushCollectionSucceeded

      it "Case 2: invalid JSON body → PubSubPushSchemaInvalid (HTTP 200 ack)" $ do
        logEnvironment <- makeTestLogEnv
        result <-
          processPubSubPushWith
            logEnvironment
            (\_ _ _ -> pure CollectionSucceeded)
            invalidJsonBody
        result `shouldSatisfy` isSchemaInvalid

      it "Case 3: valid envelope + retryable failure runner → PubSubPushWriteFailed (HTTP 500)" $ do
        logEnvironment <- makeTestLogEnv
        let body = buildPubSubBody validCloudEventValue
        result <-
          processPubSubPushWith
            logEnvironment
            (\_ _ _ -> pure (CollectionFailed DependencyUnavailable True))
            body
        result `shouldSatisfy` isWriteFailed

      it "Case 4: valid envelope + non-retryable failure runner → PubSubPushSchemaInvalid (HTTP 200)" $ do
        logEnvironment <- makeTestLogEnv
        let body = buildPubSubBody validCloudEventValue
        result <-
          processPubSubPushWith
            logEnvironment
            (\_ _ _ -> pure (CollectionFailed RequestValidationFailed False))
            body
        result `shouldSatisfy` isSchemaInvalid

    describe "MUST-15: pubSubPushResultToStatus HTTP mapping (RULE-IC-PRS-001)" $ do
      it "PubSubPushCollectionSucceeded maps to Right (HTTP 200)" $ do
        pubSubPushResultToStatus PubSubPushCollectionSucceeded
          `shouldBe` Right PubSubPushCollectionSucceeded

      it "PubSubPushCollectionDuplicate maps to Right (HTTP 200)" $ do
        pubSubPushResultToStatus PubSubPushCollectionDuplicate
          `shouldBe` Right PubSubPushCollectionDuplicate

      it "PubSubPushSchemaInvalid maps to Right (HTTP 200 — permanent failure, do not re-deliver)" $ do
        pubSubPushResultToStatus (PubSubPushSchemaInvalid "test")
          `shouldBe` Right (PubSubPushSchemaInvalid "test")

      it "PubSubPushWriteFailed maps to Left (HTTP 500 — transient, re-deliver)" $ do
        pubSubPushResultToStatus (PubSubPushWriteFailed "transient")
          `shouldSatisfy` isLeft

      it "PubSubPushDomainError maps to Left (HTTP 500 — transient, re-deliver)" $ do
        pubSubPushResultToStatus (PubSubPushDomainError "domain")
          `shouldSatisfy` isLeft

    describe "MUST-15: buildLogContext produces required fields (service/trace/identifier)" $ do
      it "service field is always 'insight-collector'" $ do
        let context = buildLogContext "insight.collect.requested" (Just "trace-val") (Just "id-val") Nothing Nothing
        context.service `shouldBe` "insight-collector"

      it "trace field is non-Nothing when provided" $ do
        let traceText = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
            context = buildLogContext "insight.collect.requested" (Just traceText) (Just "id-val") Nothing Nothing
        context.trace `shouldSatisfy` (/= Nothing)

      it "identifier field is non-Nothing when provided" $ do
        let identifierText = "01BX5ZZKBKACTAV9WEVGEMMVS0"
            context = buildLogContext "insight.collect.requested" (Just "trace-val") (Just identifierText) Nothing Nothing
        context.identifier `shouldSatisfy` (/= Nothing)

    describe "MUST-15: cloudEventToRawInsightEvent" $ do
      it "extracts targetDate as Day from valid payload" $ do
        let cloudEvent =
              CloudEvent
                { identifier = mkUlid 1
                , eventType = "insight.collect.requested"
                , occurredAt = UTCTime (fromGregorian 2026 1 15) 0
                , trace = mkUlid 2
                , schemaVersion = "1.0.0"
                , payload =
                    object
                      [ "targetDate" .= ("2026-01-15" :: Text)
                      , "requestedBy" .= ("scheduler" :: Text)
                      ]
                }
            rawEvent = cloudEventToRawInsightEvent cloudEvent
        rawEvent.targetDate `shouldBe` Just (fromGregorian 2026 1 15)

      it "extracts requestedBy Scheduler from 'scheduler'" $ do
        let cloudEvent =
              CloudEvent
                { identifier = mkUlid 1
                , eventType = "insight.collect.requested"
                , occurredAt = UTCTime (fromGregorian 2026 1 15) 0
                , trace = mkUlid 2
                , schemaVersion = "1.0.0"
                , payload =
                    object
                      [ "targetDate" .= ("2026-01-15" :: Text)
                      , "requestedBy" .= ("scheduler" :: Text)
                      ]
                }
            rawEvent = cloudEventToRawInsightEvent cloudEvent
        rawEvent.requestedBy `shouldBe` Just Scheduler

      it "trace is non-Nothing in RawInsightEvent" $ do
        let cloudEvent =
              CloudEvent
                { identifier = mkUlid 1
                , eventType = "insight.collect.requested"
                , occurredAt = UTCTime (fromGregorian 2026 1 15) 0
                , trace = mkUlid 2
                , schemaVersion = "1.0.0"
                , payload = object []
                }
            rawEvent = cloudEventToRawInsightEvent cloudEvent
        rawEvent.trace `shouldSatisfy` (/= Nothing)
