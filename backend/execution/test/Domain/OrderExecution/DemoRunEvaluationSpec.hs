module Domain.OrderExecution.DemoRunEvaluationSpec (spec) where

import Data.Either (isLeft)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.DemoRunEvaluation (
  DemoEvaluationStatus (..),
  DemoPerformance (..),
  DemoRunCompletedSpecification (..),
  DemoRunEvaluationEvent (..),
  DemoRunEvaluationIdentifier (..),
  completeDemoRun,
  isSatisfiedBy,
  markPublished,
  startDemoRun,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

endTime :: UTCTime
endTime = UTCTime (fromGregorian 2026 3 15) 0

testEvaluationIdentifier :: DemoRunEvaluationIdentifier
testEvaluationIdentifier = DemoRunEvaluationIdentifier (mkULID 2)

testTrace :: Trace
testTrace = Trace (mkULID 200)

testPerformance :: DemoPerformance
testPerformance =
  DemoPerformance
    { costAdjustedReturn = 0.15
    , dsr = Just 1.3
    , pbo = Just 0.05
    , demoPeriodDays = 60
    }

spec :: Spec
spec =
  describe "Domain.OrderExecution.DemoRunEvaluation" $ do
    -- TST-EX-007: completeDemoRun → status=Completed; markPublished sets published=True
    describe "TST-EX-007: completeDemoRun and markPublished" $ do
      it "completeDemoRun transitions to Completed" $ do
        let (evaluation, _) = startDemoRun testEvaluationIdentifier "demo-run-001" fixedTime testTrace
        case completeDemoRun endTime (Just testPerformance) Nothing evaluation of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (completed, _) -> do
            completed.status `shouldBe` Completed
            completed.endedAt `shouldBe` Just endTime
            isSatisfiedBy (DemoRunCompletedSpecification ()) completed `shouldBe` True

      it "markPublished sets published=True on Completed evaluation" $ do
        let (evaluation, _) = startDemoRun testEvaluationIdentifier "demo-run-001" fixedTime testTrace
        case completeDemoRun endTime (Just testPerformance) Nothing evaluation of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (completed, _) ->
            case markPublished completed of
              Left failure -> fail ("Unexpected Left: " ++ show failure)
              Right published -> do
                published.published `shouldBe` True

      it "completeDemoRun on already-Completed evaluation is rejected" $ do
        let (evaluation, _) = startDemoRun testEvaluationIdentifier "demo-run-001" fixedTime testTrace
        case completeDemoRun endTime (Just testPerformance) Nothing evaluation of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (completed, _) ->
            completeDemoRun endTime Nothing Nothing completed `shouldSatisfy` isLeft

      it "markPublished on Active evaluation is rejected" $ do
        let (evaluation, _) = startDemoRun testEvaluationIdentifier "demo-run-001" fixedTime testTrace
        markPublished evaluation `shouldSatisfy` isLeft

    -- TST-EX-008: DemoRunCompleted event contains trace and identifier
    describe "TST-EX-008: DemoRunCompleted event has trace and identifier" $ do
      it "DemoRunCompleted event carries trace and identifier" $ do
        let (evaluation, _) = startDemoRun testEvaluationIdentifier "demo-run-001" fixedTime testTrace
        case completeDemoRun endTime (Just testPerformance) Nothing evaluation of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (_, events) ->
            case events of
              [DemoRunCompleted{identifier = eid, trace = tr}] -> do
                eid `shouldBe` testEvaluationIdentifier
                tr `shouldBe` testTrace
              _ -> fail ("Expected 1 DemoRunCompleted event, got " ++ show (length events))

    describe "startDemoRun" $ do
      it "creates an Active evaluation with given identifier" $ do
        let (evaluation, events) = startDemoRun testEvaluationIdentifier "demo-run-001" fixedTime testTrace
        evaluation.status `shouldBe` Active
        evaluation.identifier `shouldBe` testEvaluationIdentifier
        evaluation.published `shouldBe` False
        evaluation.endedAt `shouldBe` Nothing
        events `shouldBe` []

    describe "DemoRunCompletedSpecification" $ do
      it "isSatisfiedBy returns True for Completed and unpublished" $ do
        let (evaluation, _) = startDemoRun testEvaluationIdentifier "demo-run-001" fixedTime testTrace
        case completeDemoRun endTime Nothing Nothing evaluation of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (completed, _) ->
            isSatisfiedBy (DemoRunCompletedSpecification ()) completed `shouldBe` True

      it "isSatisfiedBy returns False for Active" $ do
        let (evaluation, _) = startDemoRun testEvaluationIdentifier "demo-run-001" fixedTime testTrace
        isSatisfiedBy (DemoRunCompletedSpecification ()) evaluation `shouldBe` False

      it "isSatisfiedBy returns False for published evaluation" $ do
        let (evaluation, _) = startDemoRun testEvaluationIdentifier "demo-run-001" fixedTime testTrace
        case completeDemoRun endTime Nothing Nothing evaluation of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (completed, _) ->
            case markPublished completed of
              Left failure -> fail ("Unexpected Left: " ++ show failure)
              Right published ->
                isSatisfiedBy (DemoRunCompletedSpecification ()) published `shouldBe` False
