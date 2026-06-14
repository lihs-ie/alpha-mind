module Infrastructure.Firestore.CodeReferenceTemplateRepositorySpec (spec) where

import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Domain.HypothesisOrchestration.CodeReferenceTemplate (
  CodeReferenceTemplate (..),
  CodeReferenceTemplateRepository (..),
  CodeReferenceTemplateSearchCriteria (..),
  emptyCodeReferenceTemplateSearchCriteria,
 )
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.Firestore.CodeReferenceTemplateRepository (
  FirestoreCodeReferenceTemplateEnv (..),
  fieldsToTemplate,
  runFirestoreCodeReferenceTemplateRepositoryT,
  templateToFields,
 )
import Infrastructure.Firestore.Env (FirestoreEnv (..), FirestoreTransport (..))
import Persistence.Firestore (CollectionName, DocumentId, FirestoreError (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

testTemplate :: CodeReferenceTemplate
testTemplate =
  CodeReferenceTemplate
    { identifier = "template-001"
    , scope = "haskell"
    , content = "gs://bucket/templates/haskell-reference.md"
    , version = "2.0.0"
    }

-- ---------------------------------------------------------------------------
-- Mock transport helpers (Must-26)
-- ---------------------------------------------------------------------------

makeEnvWithGet ::
  (CollectionName -> DocumentId -> IO (Either FirestoreError (Maybe (HashMap.HashMap Text GogolFireStore.Value)))) ->
  FirestoreCodeReferenceTemplateEnv
makeEnvWithGet getDocumentFn =
  FirestoreCodeReferenceTemplateEnv
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
  FirestoreCodeReferenceTemplateEnv
makeEnvWithQuery queryResult =
  FirestoreCodeReferenceTemplateEnv
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
  describe "Infrastructure.Firestore.CodeReferenceTemplateRepository" $ do
    -- Pure codec round-trip (Must-26)
    describe "round-trip codec" $ do
      it "encodes and decodes CodeReferenceTemplate correctly" $ do
        let fields = templateToFields testTemplate
            result = fieldsToTemplate fields
        result `shouldBe` Right testTemplate

      it "must-09: returns Left DomainError when markdownPath field is missing" $ do
        let baseFields = templateToFields testTemplate
            missingMarkdownPath = HashMap.delete "markdownPath" baseFields
            result = fieldsToTemplate missingMarkdownPath
        case result of
          Left (MissingRequiredFields ["markdownPath"] ResourceNotFound) -> pure () :: IO ()
          other -> fail ("Expected MissingRequiredFields [\"markdownPath\"] ResourceNotFound, got: " <> show other)

      it "returns Left DomainError for missing identifier field" $ do
        let missingFields = HashMap.delete "identifier" (templateToFields testTemplate)
            result = fieldsToTemplate missingFields
        result `shouldSatisfy` isLeft

    -- Repository IO tests (Must-29)
    describe "find" $ do
      it "find normal case: mock returns valid document → returns Just CodeReferenceTemplate" $ do
        let fields = templateToFields testTemplate
            environment = makeEnvWithGet (\_ _ -> pure (Right (Just fields)))
        result <- runFirestoreCodeReferenceTemplateRepositoryT environment (find testTemplate.identifier)
        result `shouldBe` Just testTemplate

      it "find document absent: mock returns Nothing → returns Nothing" $ do
        let environment = makeEnvWithGet (\_ _ -> pure (Right Nothing))
        result <- runFirestoreCodeReferenceTemplateRepositoryT environment (find testTemplate.identifier)
        result `shouldBe` Nothing

      it "find field decode error: missing markdownPath → returns Nothing" $ do
        let baseFields = templateToFields testTemplate
            badFields = HashMap.delete "markdownPath" baseFields
            environment = makeEnvWithGet (\_ _ -> pure (Right (Just badFields)))
        result <- runFirestoreCodeReferenceTemplateRepositoryT environment (find testTemplate.identifier)
        result `shouldBe` Nothing

    describe "search" $ do
      it "search: mock returns field maps → returns [CodeReferenceTemplate]" $ do
        let fields = templateToFields testTemplate
            environment = makeEnvWithQuery (pure (Right [fields]))
        result <- runFirestoreCodeReferenceTemplateRepositoryT environment (search emptyCodeReferenceTemplateSearchCriteria)
        result `shouldBe` [testTemplate]
