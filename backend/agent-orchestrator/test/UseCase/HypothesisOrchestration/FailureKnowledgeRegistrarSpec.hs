module UseCase.HypothesisOrchestration.FailureKnowledgeRegistrarSpec (spec) where

import Control.Monad.State (State, modify, runState)
import Data.Either (isLeft, isRight)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.FailureKnowledge (
  FailureKnowledge (..),
  FailureKnowledgeIdentifier (..),
  FailureKnowledgeRepository (..),
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.HypothesisOrchestration.FailureKnowledgeRegistrar (registerFailure)

-- ---------------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

-- ---------------------------------------------------------------------------
-- In-memory repository for testing (test-only, lives in test/)
-- ---------------------------------------------------------------------------

data FailureKnowledgeRepoState = FailureKnowledgeRepoState
  { storedKnowledge :: Maybe FailureKnowledge
  , persistCallCount :: Int
  }

emptyState :: FailureKnowledgeRepoState
emptyState =
  FailureKnowledgeRepoState
    { storedKnowledge = Nothing
    , persistCallCount = 0
    }

newtype FailureKnowledgeTestMonad a = FailureKnowledgeTestMonad
  { runFailureKnowledgeTestMonad :: State FailureKnowledgeRepoState a
  }
  deriving newtype (Functor, Applicative, Monad)

instance FailureKnowledgeRepository FailureKnowledgeTestMonad where
  find _ = pure Nothing
  findByReasonCode _ = pure []
  search _ = pure []
  persist knowledge =
    FailureKnowledgeTestMonad $
      modify (\state -> state{storedKnowledge = Just knowledge, persistCallCount = persistCallCount state + 1})

runWith :: FailureKnowledgeRepoState -> FailureKnowledgeTestMonad a -> (a, FailureKnowledgeRepoState)
runWith initialState action = runState (runFailureKnowledgeTestMonad action) initialState

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
  describe "UseCase.HypothesisOrchestration.FailureKnowledgeRegistrar" $ do
    describe "registerFailure" $ do
      it "returns Right and persists when markdownSummary is non-empty" $ do
        let newIdentifier = FailureKnowledgeIdentifier (mkULID 42)
        let (result, finalState) =
              runWith emptyState $
                registerFailure newIdentifier ResourceNotFound "Resource missing" "## Resource Missing\nDetails here." fixedTime
        result `shouldSatisfy` isRight
        persistCallCount finalState `shouldBe` 1
        storedKnowledge finalState `shouldSatisfy` \case
          Just _ -> True
          Nothing -> False

      it "returns Left MissingRequiredFields when markdownSummary is empty" $ do
        let newIdentifier = FailureKnowledgeIdentifier (mkULID 43)
        let (result, finalState) =
              runWith emptyState $
                registerFailure newIdentifier RequestValidationFailed "Some summary" "" fixedTime
        result `shouldSatisfy` isLeft
        case result of
          Left (MissingRequiredFields ["markdownSummary"] RequestValidationFailed) -> pure ()
          other -> fail ("Expected Left MissingRequiredFields, got: " ++ show other)
        persistCallCount finalState `shouldBe` 0

      it "stores FailureKnowledge with the given reasonCode" $ do
        let newIdentifier = FailureKnowledgeIdentifier (mkULID 44)
        let (result, finalState) =
              runWith emptyState $
                registerFailure newIdentifier StateConflict "State conflict detected" "## State Conflict\nDetails." fixedTime
        result `shouldSatisfy` isRight
        case storedKnowledge finalState of
          Nothing -> fail "Expected stored FailureKnowledge"
          Just FailureKnowledge{reasonCode = storedReasonCode} ->
            storedReasonCode `shouldBe` StateConflict

      it "stores FailureKnowledge with the given summary text" $ do
        let newIdentifier = FailureKnowledgeIdentifier (mkULID 45)
        let (result, finalState) =
              runWith emptyState $
                registerFailure newIdentifier DependencyTimeout "Timeout occurred" "## Timeout\nService unavailable." fixedTime
        result `shouldSatisfy` isRight
        case storedKnowledge finalState of
          Nothing -> fail "Expected stored FailureKnowledge"
          Just FailureKnowledge{summary = storedSummary, markdownSummary = storedMarkdown} -> do
            storedSummary `shouldBe` "Timeout occurred"
            storedMarkdown `shouldBe` "## Timeout\nService unavailable."
