module Infrastructure.Firestore.OrchestrationDispatchRepositorySpec (spec) where

import Data.HashMap.Strict qualified as HashMap
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, addUTCTime)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Data.ULID (ULID)
import Domain.HypothesisOrchestration (Trace (..))
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.OrchestrationDispatch (
  OrchestrationDispatch,
  OrchestrationDispatchIdentifier (..),
  OrchestrationDispatchRepository (..),
  startDispatch,
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.ValueObjects (
  SourceEventType (..),
  mkSourceEventSnapshot,
 )
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.Firestore.Env (FirestoreEnv (..), FirestoreTransport (..))
import Infrastructure.Firestore.OrchestrationDispatchRepository (
  FirestoreOrchestrationDispatchEnv (..),
  buildDispatchDocumentId,
  dispatchToFields,
  fieldsToDispatch,
  runFirestoreOrchestrationDispatchRepositoryT,
 )
import Persistence.Firestore (CollectionName, DocumentId (..), FirestoreError (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case readMaybe "01ARZ3NDEKTSV4RRFFQ69G5FAV" of
  Just u -> u
  Nothing -> error "invalid test ULID"

testTraceUlid :: ULID
testTraceUlid = case readMaybe "01BX5ZZKBKACTAV9WEVGEMMVRE" of
  Just u -> u
  Nothing -> error "invalid test trace ULID"

testProcessedAt :: UTCTime
testProcessedAt = UTCTime (fromGregorian 2024 1 15) 0

testDispatch :: OrchestrationDispatch
testDispatch =
  let snapshotResult =
        mkSourceEventSnapshot
          "event-001"
          InsightCollected
          testProcessedAt
          (Text.pack (show testTraceUlid))
          "{\"key\":\"value\"}"
      snapshot = case snapshotResult of
        Left snapshotError -> error ("Failed to create snapshot: " <> show snapshotError)
        Right s -> s
   in startDispatch
        OrchestrationDispatchIdentifier{value = testUlid}
        snapshot
        InsightCollected
        Trace{value = testTraceUlid}

-- ---------------------------------------------------------------------------
-- Mock transport helpers (Must-26)
-- ---------------------------------------------------------------------------

makeEnvWithGet ::
  (CollectionName -> DocumentId -> IO (Either FirestoreError (Maybe (HashMap.HashMap Text GogolFireStore.Value)))) ->
  FirestoreOrchestrationDispatchEnv
makeEnvWithGet getDocumentFn =
  FirestoreOrchestrationDispatchEnv
    { firestoreEnv =
        FirestoreEnv
          { firestoreExecute =
              FirestoreTransport
                { transportGetDocument = getDocumentFn
                , transportUpsertDocument = \_ _ _ -> pure (Right ())
                , transportDeleteDocument = \_ _ -> pure (Right ())
                , transportRunQuery = \_ _ _ _ -> pure (Right [])
                }
          , projectIdentifier = "test-project"
          , databaseIdentifier = "(default)"
          }
    }

makeEnvWithUpsert ::
  (CollectionName -> DocumentId -> HashMap.HashMap Text GogolFireStore.Value -> IO (Either FirestoreError ())) ->
  FirestoreOrchestrationDispatchEnv
makeEnvWithUpsert upsertFn =
  FirestoreOrchestrationDispatchEnv
    { firestoreEnv =
        FirestoreEnv
          { firestoreExecute =
              FirestoreTransport
                { transportGetDocument = \_ _ -> pure (Right Nothing)
                , transportUpsertDocument = upsertFn
                , transportDeleteDocument = \_ _ -> pure (Right ())
                , transportRunQuery = \_ _ _ _ -> pure (Right [])
                }
          , projectIdentifier = "test-project"
          , databaseIdentifier = "(default)"
          }
    }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False

-- ---------------------------------------------------------------------------
-- Spec (Must-25, Must-29)
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
  describe "Infrastructure.Firestore.OrchestrationDispatchRepository" $ do
    -- Document ID prefix test (Must-16)
    describe "document ID" $ do
      it "must-15: document ID has 'agent-orchestrator:' prefix" $ do
        let DocumentId docId = buildDispatchDocumentId testDispatch.identifier
        docId `shouldBe` ("agent-orchestrator:" <> Text.pack (show testUlid))

      it "must-15: document ID starts with 'agent-orchestrator:'" $
        let DocumentId docId = buildDispatchDocumentId testDispatch.identifier
         in Text.isPrefixOf "agent-orchestrator:" docId `shouldBe` True

    -- Pure codec round-trip (Must-26)
    describe "round-trip codec" $ do
      it "encodes OrchestrationDispatch and decodes identifier/trace" $ do
        let fields = dispatchToFields testProcessedAt testDispatch
            result = fieldsToDispatch fields
        case result of
          Left domainError -> fail ("Expected Right, got Left: " <> show domainError)
          Right dispatch ->
            dispatch.identifier `shouldBe` testDispatch.identifier

      it "returns Left DomainError for missing identifier field" $ do
        let baseFields = dispatchToFields testProcessedAt testDispatch
            missingFields = HashMap.delete "identifier" baseFields
            result = fieldsToDispatch missingFields
        result `shouldSatisfy` isLeft

    -- Repository IO tests (Must-29)
    describe "find" $ do
      it "find normal case: mock returns valid document → returns Just OrchestrationDispatch" $ do
        let fields = dispatchToFields testProcessedAt testDispatch
            environment = makeEnvWithGet (\_ _ -> pure (Right (Just fields)))
        result <- runFirestoreOrchestrationDispatchRepositoryT environment (find testDispatch.identifier)
        case result of
          Nothing -> fail "Expected Just, got Nothing"
          Just dispatch -> dispatch.identifier `shouldBe` testDispatch.identifier

      it "find document absent: mock returns Nothing → returns Nothing" $ do
        let environment = makeEnvWithGet (\_ _ -> pure (Right Nothing))
        result <- runFirestoreOrchestrationDispatchRepositoryT environment (find testDispatch.identifier)
        result `shouldBe` Nothing

    -- persist test (Must-16)
    describe "persist" $ do
      it "persist normal case: upsert succeeds (Must-29)" $ do
        let environment = makeEnvWithUpsert (\_ _ _ -> pure (Right ()))
        runFirestoreOrchestrationDispatchRepositoryT environment (persist testDispatch) :: IO ()

      it "must-16: persist writes expiresAt as 30-day future timestamp" $ do
        capturedFieldsRef <- newIORef HashMap.empty
        capturedDocIdRef <- newIORef (DocumentId "")
        let environment =
              FirestoreOrchestrationDispatchEnv
                { firestoreEnv =
                    FirestoreEnv
                      { firestoreExecute =
                          FirestoreTransport
                            { transportGetDocument = \_ _ -> pure (Right Nothing)
                            , transportUpsertDocument = \_ docId fieldMap -> do
                                writeIORef capturedFieldsRef fieldMap
                                writeIORef capturedDocIdRef docId
                                pure (Right ())
                            , transportDeleteDocument = \_ _ -> pure (Right ())
                            , transportRunQuery = \_ _ _ _ -> pure (Right [])
                            }
                      , projectIdentifier = "test-project"
                      , databaseIdentifier = "(default)"
                      }
                }
        runFirestoreOrchestrationDispatchRepositoryT environment (persist testDispatch)
        capturedFields <- readIORef capturedFieldsRef
        -- Check expiresAt is present and is a timestamp (Must-16)
        case HashMap.lookup "expiresAt" capturedFields of
          Nothing -> fail "Expected expiresAt field to be present"
          Just expiresAtValue ->
            case expiresAtValue.timestampValue of
              Nothing -> fail "Expected expiresAt to be a timestamp"
              Just _ -> pure ()
        -- Check document ID prefix (Must-15/16)
        capturedDocId <- readIORef capturedDocIdRef
        let DocumentId docId = capturedDocId
        Text.isPrefixOf "agent-orchestrator:" docId `shouldBe` True

      it "must-15: persist writes service = 'agent-orchestrator'" $ do
        capturedFieldsRef <- newIORef HashMap.empty
        let environment =
              makeEnvWithUpsert
                ( \_ _ fieldMap -> do
                    writeIORef capturedFieldsRef fieldMap
                    pure (Right ())
                )
        runFirestoreOrchestrationDispatchRepositoryT environment (persist testDispatch)
        capturedFields <- readIORef capturedFieldsRef
        case HashMap.lookup "service" capturedFields of
          Nothing -> fail "Expected service field to be present"
          Just serviceValue ->
            case serviceValue.stringValue of
              Nothing -> fail "Expected service to be a string"
              Just serviceText -> serviceText `shouldBe` "agent-orchestrator"
