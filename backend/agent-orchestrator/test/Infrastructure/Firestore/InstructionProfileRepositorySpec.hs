module Infrastructure.Firestore.InstructionProfileRepositorySpec (spec) where

import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.InstructionProfile (
  InstructionProfile (..),
  InstructionProfileRepository (..),
  InstructionProfileSearchCriteria (..),
  emptyInstructionProfileSearchCriteria,
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.Firestore.Env (FirestoreEnv (..), FirestoreTransport (..))
import Infrastructure.Firestore.InstructionProfileRepository (
  FirestoreInstructionProfileEnv (..),
  fieldsToProfile,
  profileToFields,
  runFirestoreInstructionProfileRepositoryT,
 )
import Persistence.Firestore (CollectionName, DocumentId, FirestoreError (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

testProfile :: InstructionProfile
testProfile =
  InstructionProfile
    { identifier = "profile-001"
    , name = "hypothesis-instruction-v1"
    , version = "1.0.0"
    , content = "gs://bucket/instructions/hypothesis-v1.md"
    }

-- ---------------------------------------------------------------------------
-- Mock transport helpers (Must-26: no real GCP calls)
-- ---------------------------------------------------------------------------

makeEnvWithGet ::
  (CollectionName -> DocumentId -> IO (Either FirestoreError (Maybe (HashMap.HashMap Text GogolFireStore.Value)))) ->
  FirestoreInstructionProfileEnv
makeEnvWithGet getDocumentFn =
  FirestoreInstructionProfileEnv
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

makeEnvWithQuery ::
  IO (Either FirestoreError [HashMap.HashMap Text GogolFireStore.Value]) ->
  FirestoreInstructionProfileEnv
makeEnvWithQuery queryResult =
  FirestoreInstructionProfileEnv
    { firestoreEnv =
        FirestoreEnv
          { firestoreExecute =
              FirestoreTransport
                { transportGetDocument = \_ _ -> pure (Right Nothing)
                , transportUpsertDocument = \_ _ _ -> pure (Right ())
                , transportDeleteDocument = \_ _ -> pure (Right ())
                , transportRunQuery = \_ _ _ _ -> queryResult
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
  describe "Infrastructure.Firestore.InstructionProfileRepository" $ do
    -- Pure codec round-trip tests (Must-26: no I/O)
    describe "round-trip codec" $ do
      it "encodes and decodes InstructionProfile correctly" $ do
        let fields = profileToFields testProfile
            result = fieldsToProfile fields
        result `shouldBe` Right testProfile

      it "must-07: returns Left DomainError when contentPath field is missing" $ do
        let baseFields = profileToFields testProfile
            missingContentPath = HashMap.delete "contentPath" baseFields
            result = fieldsToProfile missingContentPath
        case result of
          Left (MissingRequiredFields ["contentPath"] ResourceNotFound) -> pure () :: IO ()
          other -> fail ("Expected MissingRequiredFields [\"contentPath\"] ResourceNotFound, got: " <> show other)

      it "returns Left DomainError for missing identifier field" $ do
        let missingFields = HashMap.delete "identifier" (profileToFields testProfile)
            result = fieldsToProfile missingFields
        result `shouldSatisfy` isLeft

    -- Repository IO tests using injected mock (Must-29)
    describe "find" $ do
      it "find normal case: mock returns valid document → returns Just InstructionProfile" $ do
        let fields = profileToFields testProfile
            environment = makeEnvWithGet (\_ _ -> pure (Right (Just fields)))
        result <- runFirestoreInstructionProfileRepositoryT environment (find testProfile.identifier)
        result `shouldBe` Just testProfile

      it "find document absent: mock returns Nothing → returns Nothing" $ do
        let environment = makeEnvWithGet (\_ _ -> pure (Right Nothing))
        result <- runFirestoreInstructionProfileRepositoryT environment (find testProfile.identifier)
        result `shouldBe` Nothing

      it "find field decode error: missing contentPath → returns Nothing" $ do
        let baseFields = profileToFields testProfile
            badFields = HashMap.delete "contentPath" baseFields
            environment = makeEnvWithGet (\_ _ -> pure (Right (Just badFields)))
        result <- runFirestoreInstructionProfileRepositoryT environment (find testProfile.identifier)
        result `shouldBe` Nothing

    describe "search" $ do
      it "search: mock returns field maps → returns [InstructionProfile]" $ do
        let fields = profileToFields testProfile
            environment = makeEnvWithQuery (pure (Right [fields]))
        result <- runFirestoreInstructionProfileRepositoryT environment (search emptyInstructionProfileSearchCriteria)
        result `shouldBe` [testProfile]
