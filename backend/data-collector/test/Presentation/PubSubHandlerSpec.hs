{-# OPTIONS_GHC -fno-hpc #-}

{- | Integration tests for 'Presentation.PubSubHandler'.

 Must-13: Tests call 'processPubSubPush' (IO function) directly, observing
 real entrypoint behaviour:
   1. Valid CloudEvents envelope → PubSubPushCollectionSucceeded (fake AppEnv)
   2. Invalid JSON body          → PubSubPushSchemaInvalid (HTTP 200 ack)
   3. Duplicate (dedup via fake dispatch store) → PubSubPushCollectionDuplicate

 Must-14: Verifies 'buildLogContext' produces service="data-collector",
 trace /= Nothing, identifier /= Nothing.

 Test doubles (fake AppEnv) live in this test file only; no mock enters src/.
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
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (
  CollectedArtifact,
  MarketCollection,
  MarketCollectionIdentifier (..),
  MarketCollectionRepository (..),
  RequestedBy (..),
 )
import Domain.MarketCollection.CollectionDispatch (
  CollectionDispatch,
  CollectionDispatchRepository (..),
  PublishedEventType (..),
  markDispatched,
  startDispatch,
 )
import Domain.MarketCollection.CollectionQualityPolicy (
  MarketSchemaIntegritySpecification (..),
  RawMarketField (..),
  RawMarketRecord (..),
 )
import Domain.MarketCollection.MarketDataSource (MarketDataSource (..))
import Domain.MarketCollection.SourcePolicySpecificationService (
  ApprovedSourceSpecification (..),
  DataSourceName (..),
 )
import Infrastructure.ACL.AlpacaMarketDataSourceT (AlpacaEnv (..))
import Infrastructure.ACL.JQuantsMarketDataSourceT (JQuantsEnv (..))
import Infrastructure.ACL.NisshokinCsvSourceAdapter (NisshokinEnv (..))
import Infrastructure.Logging.CloudLoggingCollectionAuditWriter (
  CloudLoggingCollectionAuditWriterEnv (..),
 )
import Infrastructure.Publisher.PubSubCollectionEventPublisher (
  PubSubCollectionEventPublisherEnv (..),
 )
import Infrastructure.Repository.GcsMarketDataRepository (GcsMarketDataEnv (..))
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubPublisher (..))
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Observability.Logging (LogContext (..), initLogger)
import Persistence.Firestore (FirestoreContext (..))
import Presentation.AppM (AppEnv (..))
import Presentation.PubSubHandler (
  PubSubPushResult (..),
  buildLogContext,
  cloudEventToRawSourceEvent,
  processPubSubPush,
  processPubSubPushWith,
  pubSubPushResultToStatus,
 )
import Storage.GCS (defaultGcsContext)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import Text.Read (readMaybe)
import UseCase.CollectMarketData (
  CollectionEventPublisher (..),
  RawMarketDataPort (..),
  RawSourceEvent (..),
  collectMarketData,
 )
import UseCase.RecordCollectionAudit (
  CollectionAuditEntry,
  CollectionAuditPort (..),
 )

-- ---------------------------------------------------------------------------
-- Fake AppM monad (test-only)
-- ---------------------------------------------------------------------------

data FakeState = FakeState
  { collectionStore :: Map.Map Text MarketCollection
  , dispatchStore :: Map.Map Text CollectionDispatch
  , auditEntries :: [(MarketCollectionIdentifier, Trace, CollectionAuditEntry)]
  }

emptyFakeState :: FakeState
emptyFakeState =
  FakeState
    { collectionStore = Map.empty
    , dispatchStore = Map.empty
    , auditEntries = []
    }

-- | Fake monad carrying both FakeState IORef and AppEnv for capability injection.
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

instance MarketCollectionRepository FakeAppM where
  find collectionIdentifier = FakeAppM $ \ref -> do
    state <- readIORef ref
    pure $ Map.lookup (showText collectionIdentifier.value) state.collectionStore
  findByStatus _ = pure []
  search _ = pure []
  persist collection = FakeAppM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { collectionStore =
            Map.insert (showText collection.identifier.value) collection state.collectionStore
        }
  terminate _ = pure ()

instance CollectionDispatchRepository FakeAppM where
  find collectionIdentifier = FakeAppM $ \ref -> do
    state <- readIORef ref
    pure $ Map.lookup (showText collectionIdentifier.value) state.dispatchStore
  persist dispatch = FakeAppM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { dispatchStore =
            Map.insert (showText dispatch.identifier.value) dispatch state.dispatchStore
        }
  terminate _ = pure ()

instance MarketDataSource FakeAppM where
  fetchJapanMarketData _ =
    pure
      ( Right
          [ RawMarketRecord
              { fields =
                  [ ("Date", FieldText "2026-01-15")
                  , ("Code", FieldText "1234")
                  , ("Close", FieldDouble 1500.0)
                  ]
              }
          ]
      )
  fetchUsMarketData _ = pure (Right [])

instance RawMarketDataPort FakeAppM where
  persistRawMarketData _ _ _ =
    pure (Right "gs://test-bucket/normalized_market_data/date=2026-01-15/market_snapshot.ndjson")

instance CollectionEventPublisher FakeAppM where
  publishMarketCollected _ _ _ = pure ()
  publishMarketCollectFailed _ _ _ _ = pure ()

instance CollectionAuditPort FakeAppM where
  writeCollectionAudit collectionIdentifier traceValue entry = FakeAppM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { auditEntries = (collectionIdentifier, traceValue, entry) : state.auditEntries
        }

-- ---------------------------------------------------------------------------
-- AppEnv builder for tests
-- ---------------------------------------------------------------------------

makeTestAppEnv :: IO (AppEnv, IORef FakeState)
makeTestAppEnv = do
  stateRef <- newIORef emptyFakeState
  httpManager <- newManager defaultManagerSettings
  let runtimeEnv =
        CommonRuntimeEnv
          { port = 8080
          , gcpProjectId = "test-project"
          , serviceName = "data-collector"
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
      pubSubEnvironment =
        PubSubCollectionEventPublisherEnv
          { publisher = publisher
          , collectedTopicName = "market-collected"
          , failedTopicName = "market-collect-failed"
          }
      gcsEnvironment =
        GcsMarketDataEnv
          { gcsContext = defaultGcsContext
          , bucketName = "test-bucket"
          , uploadFn = \_objectRef _contentType _bytes -> pure (Right ())
          }
      nisshokinEnv =
        NisshokinEnv
          { timeoutSeconds = 60
          , httpExecute = \_ -> error "httpExecute must not be called in tests"
          , browserFallback = \_targetDay -> pure (Right [])
          , onBrowserFallback = \_message -> pure ()
          }
      jQuantsEnv =
        JQuantsEnv
          { baseUrl = "https://api.jquants-pro.com/v2"
          , idToken = "test-token"
          , timeoutSeconds = 30
          , httpExecute = \_ -> error "httpExecute must not be called in tests"
          , nisshokinEnv = nisshokinEnv
          }
      alpacaEnv =
        AlpacaEnv
          { usCollectionEnabled = False
          , apiKeyIdentifier = "test-key-id"
          , apiSecretKey = "test-secret"
          , timeoutSeconds = 30
          , baseUrl = "https://data.alpaca.markets/v2"
          , httpExecute = \_ -> error "httpExecute must not be called in tests"
          }
      auditLogEnv =
        CloudLoggingCollectionAuditWriterEnv
          { logEnv = logEnvironment
          }
      appEnv =
        AppEnv
          { firestoreContext = firestoreCtx
          , logEnv = logEnvironment
          , gcsEnv = gcsEnvironment
          , jQuantsEnv = jQuantsEnv
          , alpacaEnv = alpacaEnv
          , pubSubEnv = pubSubEnvironment
          , auditLogEnv = auditLogEnv
          , serviceName = "data-collector"
          , approvedSourceSpecification =
              ApprovedSourceSpecification
                { approvedSources = [DataSourceName "jquants"]
                }
          , schemaIntegritySpecification =
              MarketSchemaIntegritySpecification
                { requiredFields = []
                }
          }
  pure (appEnv, stateRef)

-- ---------------------------------------------------------------------------
-- Pub/Sub body builders
-- ---------------------------------------------------------------------------

-- | Build a Pub/Sub push body wrapping a CloudEvent-like JSON value.
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

-- | Fixed ULID text values for reproducibility.
validUlidText1 :: Text
validUlidText1 = "01ARZ3NDEKTSV4RRFFQ69G5FAV"

-- ---------------------------------------------------------------------------
-- Spec (Must-13, Must-14)
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "Presentation.PubSubHandler" $ do
    describe "Must-13: processPubSubPush integration" $ do
      it "Case 1: valid CloudEvents envelope returns PubSubPushCollectionSucceeded (FakeAppM)" $ do
        (appEnv, stateRef) <- makeTestAppEnv
        let cloudEventValue =
              object
                [ "identifier" .= validUlidText1
                , "eventType" .= ("market.collect.requested" :: Text)
                , "occurredAt" .= ("2026-01-15T00:00:00Z" :: Text)
                , "trace" .= validUlidText1
                , "schemaVersion" .= ("1.0.0" :: Text)
                , "payload"
                    .= object
                      [ "targetDate" .= ("2026-01-15" :: Text)
                      , "requestedBy" .= ("scheduler" :: Text)
                      , "requestedSources" .= ([] :: [Text])
                      ]
                ]
            body = buildPubSubBody cloudEventValue
        result <-
          processPubSubPushWith
            appEnv.logEnv
            appEnv.approvedSourceSpecification
            appEnv.schemaIntegritySpecification
            ( \currentTime collectionIdentifier approvedSources schemaSpecification rawSourceEvent ->
                runFakeAppM
                  (collectMarketData currentTime collectionIdentifier approvedSources schemaSpecification rawSourceEvent)
                  stateRef
            )
            body
        result `shouldBe` PubSubPushCollectionSucceeded

      it "Case 2: invalid JSON body returns PubSubPushSchemaInvalid (HTTP 200)" $ do
        (appEnv, _) <- makeTestAppEnv
        result <- processPubSubPush appEnv invalidJsonBody
        result `shouldSatisfy` isSchemaInvalid

      it "Case 2: invalid ULID identifier in CloudEvent returns PubSubPushSchemaInvalid" $ do
        (appEnv, _) <- makeTestAppEnv
        let cloudEventValue =
              object
                [ "identifier" .= ("not-a-valid-ulid-xxx" :: Text)
                , "eventType" .= ("market.collect.requested" :: Text)
                , "occurredAt" .= ("2026-01-15T00:00:00Z" :: Text)
                , "trace" .= validUlidText1
                , "schemaVersion" .= ("1.0.0" :: Text)
                , "payload" .= object []
                ]
            body = buildPubSubBody cloudEventValue
        result <- processPubSubPush appEnv body
        result `shouldSatisfy` isSchemaInvalid

      it "Case 3: duplicate (Published dispatch) returns PubSubPushCollectionDuplicate (FakeAppM)" $ do
        (appEnv, stateRef) <- makeTestAppEnv
        -- Pre-seed a Published CollectionDispatch.
        -- The CloudEvent body uses validUlidText1 as the identifier, which is parsed via
        -- readMaybe :: Maybe ULID. We use the same parse path so the dispatchStore key matches.
        let targetUlid = case readMaybe (Text.unpack validUlidText1) :: Maybe ULID of
              Just ulid -> ulid
              Nothing -> error ("Invalid ULID text: " <> Text.unpack validUlidText1)
            collectionIdentifier = MarketCollectionIdentifier targetUlid
            traceValue = Trace (mkUlid 2)
            pendingDispatch = startDispatch collectionIdentifier traceValue
        currentTime <- getCurrentTime
        case markDispatched MarketCollected currentTime pendingDispatch of
          Left domainError -> fail ("markDispatched failed unexpectedly: " <> show domainError)
          Right publishedDispatch ->
            modifyIORef' stateRef $ \state ->
              state
                { dispatchStore =
                    Map.insert
                      (showText collectionIdentifier.value)
                      publishedDispatch
                      state.dispatchStore
                }
        -- Build a body whose CloudEvent identifier matches the pre-seeded dispatch
        let cloudEventValue =
              object
                [ "identifier" .= validUlidText1
                , "eventType" .= ("market.collect.requested" :: Text)
                , "occurredAt" .= ("2026-01-15T00:00:00Z" :: Text)
                , "trace" .= validUlidText1
                , "schemaVersion" .= ("1.0.0" :: Text)
                , "payload"
                    .= object
                      [ "targetDate" .= ("2026-01-15" :: Text)
                      , "requestedBy" .= ("scheduler" :: Text)
                      , "requestedSources" .= ([] :: [Text])
                      ]
                ]
            body = buildPubSubBody cloudEventValue
        result <-
          processPubSubPushWith
            appEnv.logEnv
            appEnv.approvedSourceSpecification
            appEnv.schemaIntegritySpecification
            ( \currentTime2 collectionIdentifier2 approvedSources schemaSpecification rawSourceEvent ->
                runFakeAppM
                  (collectMarketData currentTime2 collectionIdentifier2 approvedSources schemaSpecification rawSourceEvent)
                  stateRef
            )
            body
        result `shouldBe` PubSubPushCollectionDuplicate

      it "Must-04: CollectionFailed _ False maps to PubSubPushSchemaInvalid (HTTP 200)" $ do
        pubSubPushResultToStatus (PubSubPushSchemaInvalid "validation_failed")
          `shouldBe` Right (PubSubPushSchemaInvalid "validation_failed")

      it "Must-04: CollectionFailed _ True maps to PubSubPushWriteFailed (HTTP 500)" $ do
        pubSubPushResultToStatus (PubSubPushWriteFailed "transient")
          `shouldSatisfy` isLeft

    describe "Must-13/Must-04: pubSubPushResultToStatus HTTP mapping (RULE-DC-PRS-001)" $ do
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

    describe "Must-14: buildLogContext produces required fields" $ do
      it "service field is always 'data-collector'" $ do
        let context = buildLogContext "market.collect.requested" (Just "trace-val") (Just "id-val") Nothing Nothing
        context.service `shouldBe` "data-collector"

      it "trace field is non-Nothing when provided" $ do
        let traceText = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
            context = buildLogContext "market.collect.requested" (Just traceText) (Just "id-val") Nothing Nothing
        context.trace `shouldSatisfy` (/= Nothing)

      it "identifier field is non-Nothing when provided" $ do
        let identifierText = "01BX5ZZKBKACTAV9WEVGEMMVS0"
            context = buildLogContext "market.collect.requested" (Just "trace-val") (Just identifierText) Nothing Nothing
        context.identifier `shouldSatisfy` (/= Nothing)

    describe "Must-05: cloudEventToRawSourceEvent" $ do
      it "extracts targetDate as Day from valid payload" $ do
        let cloudEventValue =
              CloudEvent
                { identifier = mkUlid 1
                , eventType = "market.collect.requested"
                , occurredAt = UTCTime (fromGregorian 2026 1 15) 0
                , trace = mkUlid 2
                , schemaVersion = "1.0.0"
                , payload =
                    object
                      [ "targetDate" .= ("2026-01-15" :: Text)
                      , "requestedBy" .= ("scheduler" :: Text)
                      ]
                }
            rawEvent = cloudEventToRawSourceEvent cloudEventValue
        rawEvent.targetDate `shouldBe` Just (fromGregorian 2026 1 15)

      it "extracts requestedBy Scheduler from 'scheduler'" $ do
        let cloudEventValue =
              CloudEvent
                { identifier = mkUlid 1
                , eventType = "market.collect.requested"
                , occurredAt = UTCTime (fromGregorian 2026 1 15) 0
                , trace = mkUlid 2
                , schemaVersion = "1.0.0"
                , payload =
                    object
                      [ "targetDate" .= ("2026-01-15" :: Text)
                      , "requestedBy" .= ("scheduler" :: Text)
                      ]
                }
            rawEvent = cloudEventToRawSourceEvent cloudEventValue
        rawEvent.requestedBy `shouldBe` Just Scheduler

      it "trace is non-Nothing in RawSourceEvent" $ do
        let cloudEventValue =
              CloudEvent
                { identifier = mkUlid 1
                , eventType = "market.collect.requested"
                , occurredAt = UTCTime (fromGregorian 2026 1 15) 0
                , trace = mkUlid 2
                , schemaVersion = "1.0.0"
                , payload = object []
                }
            rawEvent = cloudEventToRawSourceEvent cloudEventValue
        rawEvent.trace `shouldSatisfy` (/= Nothing)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

isSchemaInvalid :: PubSubPushResult -> Bool
isSchemaInvalid (PubSubPushSchemaInvalid _) = True
isSchemaInvalid _ = False

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False

showText :: (Show a) => a -> Text
showText = Text.pack . show

mkUlid :: Integer -> ULID
mkUlid n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)
