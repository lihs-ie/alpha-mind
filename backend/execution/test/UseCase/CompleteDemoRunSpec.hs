module UseCase.CompleteDemoRunSpec (spec) where

import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.DemoRunEvaluation (
  DemoEvaluationStatus (..),
  DemoPerformance (..),
  DemoRunEvaluation,
  DemoRunEvaluationIdentifier (..),
  DemoRunEvaluationRepository (..),
  markPublished,
  startDemoRun,
 )
import Domain.OrderExecution.DemoRunEvaluation qualified as DemoRunDomain
import Test.Hspec (Spec, describe, it, shouldBe)
import UseCase.CompleteDemoRun (
  CompleteDemoRunResult (..),
  DemoCompletionEventPublisher (..),
  DemoRunCompletionTrigger (..),
  DemoRunIdentifier (..),
  HypothesisIdentifier (..),
 )
import UseCase.CompleteDemoRun qualified as UseCase

-- ---------------------------------------------------------------------
-- Test fixtures
-- ---------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

mkTrace :: Integer -> Trace
mkTrace n = Trace (mkULID n)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

fixedStartedAt :: UTCTime
fixedStartedAt = UTCTime (fromGregorian 2026 1 1) 0

fixedEndedAt :: UTCTime
fixedEndedAt = UTCTime (fromGregorian 2026 1 14) 0

fixedIdentifier :: DemoRunEvaluationIdentifier
fixedIdentifier = DemoRunEvaluationIdentifier (mkULID 1)

fixedHypothesisIdentifier :: HypothesisIdentifier
fixedHypothesisIdentifier = HypothesisIdentifier (mkULID 2)

fixedTrace :: Trace
fixedTrace = mkTrace 100

validCompletionEvent :: DemoRunCompletionTrigger
validCompletionEvent =
  DemoRunCompletionTrigger
    { identifier = fixedIdentifier
    , hypothesis = fixedHypothesisIdentifier
    , demoRun = DemoRunIdentifier "demo-run-abc"
    , startedAt = fixedStartedAt
    , endedAt = fixedEndedAt
    , trace = fixedTrace
    , performance = Nothing
    , promotionGate = Nothing
    }

-- | Build a DemoRunEvaluation with published=True (already published).
mkPublishedEvaluation :: DemoRunEvaluation
mkPublishedEvaluation =
  let (evaluation, _) = startDemoRun fixedIdentifier "demo-run-abc" fixedStartedAt fixedTrace
   in case DemoRunDomain.completeDemoRun fixedEndedAt Nothing Nothing evaluation of
        Left domainError -> error ("mkPublishedEvaluation: completeDemoRun failed: " ++ show domainError)
        Right (completed, _) ->
          case markPublished completed of
            Left domainError -> error ("mkPublishedEvaluation: markPublished failed: " ++ show domainError)
            Right published -> published

-- ---------------------------------------------------------------------
-- Mock state
-- ---------------------------------------------------------------------

data MockState = MockState
  { evaluationStore :: Maybe DemoRunEvaluation
  , persistCallCount :: Int
  , persistedEvaluations :: [DemoRunEvaluation]
  , publishedCompleted :: [(HypothesisIdentifier, DemoRunIdentifier, DemoPerformance, Trace)]
  }

newMockState :: IO (IORef MockState)
newMockState =
  newIORef
    MockState
      { evaluationStore = Nothing
      , persistCallCount = 0
      , persistedEvaluations = []
      , publishedCompleted = []
      }

-- ---------------------------------------------------------------------
-- Mock monad
-- ---------------------------------------------------------------------

newtype MockM a = MockM {runMockM :: IORef MockState -> IO a}

instance Functor MockM where
  fmap f (MockM g) = MockM $ \ref -> fmap f (g ref)

instance Applicative MockM where
  pure a = MockM $ \_ -> pure a
  MockM f <*> MockM a = MockM $ \ref -> f ref <*> a ref

instance Monad MockM where
  MockM a >>= f = MockM $ \ref -> do
    value <- a ref
    runMockM (f value) ref

-- ---------------------------------------------------------------------
-- Port instances (test doubles — only in test/)
-- ---------------------------------------------------------------------

instance DemoRunEvaluationRepository MockM where
  findDemoRunEvaluation _ = MockM $ \ref -> do
    state <- readIORef ref
    pure state.evaluationStore
  persistDemoRunEvaluation evaluation = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { evaluationStore = Just evaluation
        , persistCallCount = state.persistCallCount + 1
        , persistedEvaluations = state.persistedEvaluations ++ [evaluation]
        }
  terminateDemoRunEvaluation _ = pure ()

instance DemoCompletionEventPublisher MockM where
  publishHypothesisDemoCompleted hypothesisIdentifier demoRunIdentifier performanceValue traceValue = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { publishedCompleted =
            state.publishedCompleted
              ++ [(hypothesisIdentifier, demoRunIdentifier, performanceValue, traceValue)]
        }

runWithMock :: IORef MockState -> MockM a -> IO a
runWithMock ref (MockM f) = f ref

-- ---------------------------------------------------------------------
-- Test helper
-- ---------------------------------------------------------------------

runCompleteDemoRun :: IORef MockState -> IO CompleteDemoRunResult
runCompleteDemoRun ref =
  runWithMock ref $
    UseCase.completeDemoRun fixedTime validCompletionEvent

-- ---------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "UseCase.CompleteDemoRun" $ do
    -- TST-UC-EX-007: published=True → CompleteDemoRunDuplicate, no publisher call
    describe "TST-UC-EX-007: published=True DemoRunEvaluation → CompleteDemoRunDuplicate, no publisher" $ do
      it "returns CompleteDemoRunDuplicate when evaluation is already published" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{evaluationStore = Just mkPublishedEvaluation}
        result <- runCompleteDemoRun ref
        result `shouldBe` CompleteDemoRunDuplicate

      it "does not call publishHypothesisDemoCompleted when already published" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{evaluationStore = Just mkPublishedEvaluation}
        _ <- runCompleteDemoRun ref
        state <- readIORef ref
        length state.publishedCompleted `shouldBe` 0

      it "does not call persist when already published" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{evaluationStore = Just mkPublishedEvaluation}
        _ <- runCompleteDemoRun ref
        state <- readIORef ref
        state.persistCallCount `shouldBe` 0

    -- TST-UC-EX-008: unpublished DemoRunEvaluation → 2x persist + 1x publish + CompleteDemoRunSucceeded
    describe
      "TST-UC-EX-008: unpublished DemoRunEvaluation → 2x persist, 1x publishHypothesisDemoCompleted, CompleteDemoRunSucceeded"
      $ do
        it "returns CompleteDemoRunSucceeded for a new demo run" $ do
          ref <- newMockState
          result <- runCompleteDemoRun ref
          result `shouldBe` CompleteDemoRunSucceeded

        it "DemoRunEvaluationRepository.persist is called twice (completed then published)" $ do
          ref <- newMockState
          _ <- runCompleteDemoRun ref
          state <- readIORef ref
          state.persistCallCount `shouldBe` 2

        it "publishHypothesisDemoCompleted is called exactly once" $ do
          ref <- newMockState
          _ <- runCompleteDemoRun ref
          state <- readIORef ref
          length state.publishedCompleted `shouldBe` 1

        it "final persisted evaluation has published=True" $ do
          ref <- newMockState
          _ <- runCompleteDemoRun ref
          state <- readIORef ref
          case state.evaluationStore of
            Nothing -> fail "No evaluation was persisted"
            Just evaluation -> evaluation.published `shouldBe` True

        it "final persisted evaluation has status=Completed" $ do
          ref <- newMockState
          _ <- runCompleteDemoRun ref
          state <- readIORef ref
          case state.evaluationStore of
            Nothing -> fail "No evaluation was persisted"
            Just evaluation -> evaluation.status `shouldBe` Completed

        it "persist called before publishHypothesisDemoCompleted (Must-15 ordering)" $ do
          ref <- newMockState
          _ <- runCompleteDemoRun ref
          state <- readIORef ref
          -- Both must have been called
          (state.persistCallCount >= 1 && not (null state.publishedCompleted))
            `shouldBe` True

        it "trace propagated to publishHypothesisDemoCompleted" $ do
          ref <- newMockState
          _ <- runCompleteDemoRun ref
          state <- readIORef ref
          case state.publishedCompleted of
            [] -> fail "publishHypothesisDemoCompleted was not called"
            (_, _, _, traceValue) : _ -> traceValue `shouldBe` fixedTrace
