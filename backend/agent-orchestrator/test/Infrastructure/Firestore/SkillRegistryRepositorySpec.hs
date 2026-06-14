module Infrastructure.Firestore.SkillRegistryRepositorySpec (spec) where

import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.SkillRegistry (
  Skill (..),
  SkillRegistryRepository (..),
  SkillStatus (..),
 )
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.Firestore.Env (FirestoreEnv (..), FirestoreTransport (..))
import Infrastructure.Firestore.SkillRegistryRepository (
  FirestoreSkillRegistryEnv (..),
  fieldsToSkill,
  runFirestoreSkillRegistryRepositoryT,
  skillToFields,
 )
import Persistence.Firestore (CollectionName, DocumentId, FirestoreError (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

testSkill :: Skill
testSkill =
  Skill
    { identifier = "01H2X3Y4Z5A6B7C8D9E0F1G2H3"
    , name = "hypothesis-generation"
    , version = "1.0.0"
    , status = SkillActive
    }

-- ---------------------------------------------------------------------------
-- Mock transport helpers (Must-26: no real GCP calls)
-- ---------------------------------------------------------------------------

makeEnvWithGet ::
  (CollectionName -> DocumentId -> IO (Either FirestoreError (Maybe (HashMap.HashMap Text GogolFireStore.Value)))) ->
  FirestoreSkillRegistryEnv
makeEnvWithGet getDocumentFn =
  FirestoreSkillRegistryEnv
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
  describe "Infrastructure.Firestore.SkillRegistryRepository" $ do
    -- Pure codec round-trip (no I/O) — Must-26
    describe "round-trip codec" $ do
      it "encodes and decodes Skill correctly" $ do
        let fields = skillToFields testSkill
            result = fieldsToSkill fields
        result `shouldBe` Right testSkill

      it "must-05: returns Left DomainError for unknown status value" $ do
        let baseFields = skillToFields testSkill
            badFields =
              HashMap.insert
                "status"
                (GogolFireStore.newValue{GogolFireStore.stringValue = Just "unknown_status"})
                baseFields
            result = fieldsToSkill badFields
        case result of
          Left (MissingRequiredFields _ RequestValidationFailed) -> pure () :: IO ()
          other -> fail ("Expected Left DomainError with RequestValidationFailed, got: " <> show other)

      it "returns Left DomainError for missing required field" $ do
        let missingFields = HashMap.delete "name" (skillToFields testSkill)
            result = fieldsToSkill missingFields
        result `shouldSatisfy` isLeft

    -- Repository IO tests via injected mock (Must-29)
    describe "find" $ do
      it "find normal case: mock returns valid document → returns Just Skill" $ do
        let fields = skillToFields testSkill
            environment = makeEnvWithGet (\_ _ -> pure (Right (Just fields)))
        result <- runFirestoreSkillRegistryRepositoryT environment (find testSkill.identifier)
        result `shouldBe` Just testSkill

      it "find document absent: mock returns Nothing → returns Nothing" $ do
        let environment = makeEnvWithGet (\_ _ -> pure (Right Nothing))
        result <- runFirestoreSkillRegistryRepositoryT environment (find testSkill.identifier)
        result `shouldBe` Nothing

      it "find transport error: mock returns Left → returns Nothing" $ do
        let environment = makeEnvWithGet (\_ _ -> pure (Left (FirestoreErrorTransport "network error")))
        result <- runFirestoreSkillRegistryRepositoryT environment (find testSkill.identifier)
        result `shouldBe` Nothing

    -- persist test (Must-29)
    describe "persist (no-op environment)" $ do
      it "findByStatus normal case: mock returns field maps → returns [Skill]" $ do
        let fields = skillToFields testSkill
            environment =
              FirestoreSkillRegistryEnv
                { firestoreEnv =
                    FirestoreEnv
                      { firestoreExecute =
                          FirestoreTransport
                            { transportGetDocument = \_ _ -> pure (Right Nothing)
                            , transportUpsertDocument = \_ _ _ -> pure (Right ())
                            , transportDeleteDocument = \_ _ -> pure (Right ())
                            , transportRunQuery = \_ _ _ _ -> pure (Right [fields])
                            }
                      , projectIdentifier = "test-project"
                      , databaseIdentifier = "(default)"
                      }
                }
        result <- runFirestoreSkillRegistryRepositoryT environment (findByStatus SkillActive)
        result `shouldBe` [testSkill]
