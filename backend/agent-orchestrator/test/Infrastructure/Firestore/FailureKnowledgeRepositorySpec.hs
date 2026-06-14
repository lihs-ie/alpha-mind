module Infrastructure.Firestore.FailureKnowledgeRepositorySpec (spec) where

import Data.HashMap.Strict qualified as HashMap
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Data.ULID (ULID)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.FailureKnowledge (
  FailureKnowledge (..),
  FailureKnowledgeIdentifier (..),
  FailureKnowledgeRepository (..),
  emptyFailureKnowledgeSearchCriteria,
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.Firestore.Env (FirestoreEnv (..), FirestoreTransport (..))
import Infrastructure.Firestore.FailureKnowledgeRepository (
  FirestoreFailureKnowledgeEnv (..),
  fieldsToKnowledge,
  knowledgeToFields,
  runFirestoreFailureKnowledgeRepositoryT,
 )
import Persistence.Firestore (CollectionName, DocumentId, FirestoreError (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case readMaybe "01ARZ3NDEKTSV4RRFFQ69G5FAV" of
  Just u -> u
  Nothing -> error "invalid test ULID"

testRecordedAt :: UTCTime
testRecordedAt = UTCTime (fromGregorian 2024 1 15) 0

testKnowledge :: FailureKnowledge
testKnowledge =
  FailureKnowledge
    { identifier = FailureKnowledgeIdentifier{value = testUlid}
    , reasonCode = DependencyTimeout
    , summary = "Dependency timed out during data collection"
    , markdownSummary = "# Failure\n\nDependency timed out."
    , similarityHash = "sha256-abc123def456"
    , recordedAt = testRecordedAt
    }

-- ---------------------------------------------------------------------------
-- Mock transport helpers (Must-26)
-- ---------------------------------------------------------------------------

makeEnvWithGet ::
  (CollectionName -> DocumentId -> IO (Either FirestoreError (Maybe (HashMap.HashMap Text GogolFireStore.Value)))) ->
  FirestoreFailureKnowledgeEnv
makeEnvWithGet getDocumentFn =
  FirestoreFailureKnowledgeEnv
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
  FirestoreFailureKnowledgeEnv
makeEnvWithUpsert upsertFn =
  FirestoreFailureKnowledgeEnv
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
  describe "Infrastructure.Firestore.FailureKnowledgeRepository" $ do
    -- Pure codec round-trip (Must-26)
    describe "round-trip codec" $ do
      it "encodes and decodes FailureKnowledge correctly" $ do
        let fields = knowledgeToFields testKnowledge
            result = fieldsToKnowledge fields
        result `shouldBe` Right testKnowledge

      it "returns Left DomainError for missing reasonCode field" $ do
        let missingFields = HashMap.delete "reasonCode" (knowledgeToFields testKnowledge)
            result = fieldsToKnowledge missingFields
        result `shouldSatisfy` isLeft

      it "returns Left DomainError for missing identifier field" $ do
        let missingFields = HashMap.delete "identifier" (knowledgeToFields testKnowledge)
            result = fieldsToKnowledge missingFields
        result `shouldSatisfy` isLeft

    -- Repository IO tests (Must-29)
    describe "find" $ do
      it "find normal case: mock returns valid document → returns Just FailureKnowledge" $ do
        let fields = knowledgeToFields testKnowledge
            environment = makeEnvWithGet (\_ _ -> pure (Right (Just fields)))
        result <- runFirestoreFailureKnowledgeRepositoryT environment (find testKnowledge.identifier)
        result `shouldBe` Just testKnowledge

      it "find document absent: mock returns Nothing → returns Nothing" $ do
        let environment = makeEnvWithGet (\_ _ -> pure (Right Nothing))
        result <- runFirestoreFailureKnowledgeRepositoryT environment (find testKnowledge.identifier)
        result `shouldBe` Nothing

      it "find field decode error: missing required field → returns Nothing" $ do
        let badFields = HashMap.delete "markdownSummary" (knowledgeToFields testKnowledge)
            environment = makeEnvWithGet (\_ _ -> pure (Right (Just badFields)))
        result <- runFirestoreFailureKnowledgeRepositoryT environment (find testKnowledge.identifier)
        result `shouldBe` Nothing

    -- persist test (Must-11: createdAt is RFC3339 timestamp)
    describe "persist" $ do
      it "persist normal case: mock upsert succeeds without exception (Must-29)" $ do
        let environment = makeEnvWithUpsert (\_ _ _ -> pure (Right ()))
        runFirestoreFailureKnowledgeRepositoryT environment (persist testKnowledge) :: IO ()

      it "must-11: persist writes createdAt field as UTCTime (timestamp)" $ do
        capturedFieldsRef <- newIORef HashMap.empty
        let environment =
              makeEnvWithUpsert
                ( \_ _ fieldMap -> do
                    writeIORef capturedFieldsRef fieldMap
                    pure (Right ())
                )
        runFirestoreFailureKnowledgeRepositoryT environment (persist testKnowledge)
        capturedFields <- readIORef capturedFieldsRef
        case HashMap.lookup "createdAt" capturedFields of
          Nothing -> fail "Expected createdAt field to be present"
          Just createdAtValue ->
            case createdAtValue.timestampValue of
              Nothing -> fail "Expected createdAt to be a timestamp"
              Just _ -> pure ()
