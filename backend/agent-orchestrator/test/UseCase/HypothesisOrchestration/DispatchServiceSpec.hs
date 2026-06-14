module UseCase.HypothesisOrchestration.DispatchServiceSpec (spec) where

import Control.Monad.State (State, gets, modify, runState)
import Data.Either (isLeft, isRight)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.HypothesisOrchestration (Trace (..))
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.OrchestrationDispatch (
  OrchestrationDispatch,
  OrchestrationDispatchIdentifier (..),
  OrchestrationDispatchRepository (..),
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.ValueObjects (
  SourceEventSnapshot,
  SourceEventType (..),
  mkSourceEventSnapshot,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.HypothesisOrchestration.DispatchService (checkIdempotency)

-- ---------------------------------------------------------------------------
-- Test helper types
-- ---------------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

testTrace :: Trace
testTrace = Trace (mkULID 100)

testDispatchIdentifier :: OrchestrationDispatchIdentifier
testDispatchIdentifier = OrchestrationDispatchIdentifier (mkULID 1)

mkTestSnapshot :: SourceEventSnapshot
mkTestSnapshot =
  case mkSourceEventSnapshot "evt-001" InsightCollected fixedTime "trace-001" "{}" of
    Right snapshot -> snapshot
    Left parseError -> error ("mkTestSnapshot: " ++ show parseError)

-- ---------------------------------------------------------------------------
-- In-memory repository for testing (test-only, lives in test/)
-- ---------------------------------------------------------------------------

-- | Minimal in-memory state for dispatch repository tests.
data DispatchRepoState = DispatchRepoState
  { storedDispatch :: Maybe OrchestrationDispatch
  , persistCallCount :: Int
  }

emptyDispatchRepoState :: DispatchRepoState
emptyDispatchRepoState =
  DispatchRepoState
    { storedDispatch = Nothing
    , persistCallCount = 0
    }

newtype DispatchTestMonad a = DispatchTestMonad
  { runDispatchTestMonad :: State DispatchRepoState a
  }
  deriving newtype (Functor, Applicative, Monad)

instance OrchestrationDispatchRepository DispatchTestMonad where
  find _ = DispatchTestMonad (gets storedDispatch)
  persist dispatch =
    DispatchTestMonad $
      modify (\state -> state{storedDispatch = Just dispatch, persistCallCount = persistCallCount state + 1})
  terminate _ = pure ()

runWith :: DispatchRepoState -> DispatchTestMonad a -> (a, DispatchRepoState)
runWith initialState action = runState (runDispatchTestMonad action) initialState

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
  describe "UseCase.HypothesisOrchestration.DispatchService" $ do
    describe "checkIdempotency" $ do
      it "returns Right dispatch when no existing dispatch found" $ do
        let (result, finalState) =
              runWith emptyDispatchRepoState $
                checkIdempotency testDispatchIdentifier mkTestSnapshot testTrace fixedTime
        result `shouldSatisfy` isRight
        persistCallCount finalState `shouldBe` 1

      it "returns Left AlreadyProcessed when dispatch already exists" $ do
        -- First call to create dispatch
        let (firstResult, stateAfterFirst) =
              runWith emptyDispatchRepoState $
                checkIdempotency testDispatchIdentifier mkTestSnapshot testTrace fixedTime
        firstResult `shouldSatisfy` isRight
        -- Second call with same identifier should be duplicate
        let (secondResult, _) =
              runWith stateAfterFirst $
                checkIdempotency testDispatchIdentifier mkTestSnapshot testTrace fixedTime
        secondResult `shouldSatisfy` isLeft
        case secondResult of
          Left (AlreadyProcessed IdempotencyDuplicateEvent) -> pure ()
          other -> fail ("Expected Left (AlreadyProcessed IdempotencyDuplicateEvent), got: " ++ show other)

      it "persists dispatch on successful creation" $ do
        let (_, finalState) =
              runWith emptyDispatchRepoState $
                checkIdempotency testDispatchIdentifier mkTestSnapshot testTrace fixedTime
        persistCallCount finalState `shouldBe` 1
        storedDispatch finalState `shouldSatisfy` \case
          Just _ -> True
          Nothing -> False

      it "persists Duplicate-state dispatch on duplicate detection (audit trail)" $ do
        let (_, stateAfterFirst) =
              runWith emptyDispatchRepoState $
                checkIdempotency testDispatchIdentifier mkTestSnapshot testTrace fixedTime
        -- Second call should persist the markDuplicate result for audit
        let (_, finalState) =
              runWith stateAfterFirst $
                checkIdempotency testDispatchIdentifier mkTestSnapshot testTrace fixedTime
        -- persist called twice: once for creation, once for duplicate-state update
        persistCallCount finalState `shouldBe` 2
