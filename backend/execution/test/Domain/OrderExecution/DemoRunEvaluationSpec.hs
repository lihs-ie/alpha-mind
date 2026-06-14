module Domain.OrderExecution.DemoRunEvaluationSpec (spec) where

import Data.Either (isLeft)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.DemoRunEvaluation (
  DemoPerformance (..),
  DemoRun (..),
  DemoRunCompletedSpecification (..),
  DemoRunEvaluation,
  DemoRunEvaluationEvent (..),
  DemoRunEvaluationIdentifier (..),
  DemoRunStatus (..),
  InsiderRisk (..),
  InstrumentType (..),
  PromotionGate (..),
  completeDemoRun,
  isDemoRunCompleted,
  markPublished,
  startDemoRun,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

testIdentifier :: DemoRunEvaluationIdentifier
testIdentifier = DemoRunEvaluationIdentifier (mkULID 1)

testDemoRun :: DemoRun
testDemoRun = DemoRun "demo-20260115-001"

testTrace :: Trace
testTrace = Trace (mkULID 100)

startedAt :: UTCTime
startedAt = UTCTime (fromGregorian 2025 12 1) 0

endedAt :: UTCTime
endedAt = UTCTime (fromGregorian 2026 1 15) 0

testPerformance :: DemoPerformance
testPerformance =
  DemoPerformance
    { costAdjustedReturn = Just 4.2
    , dsr = Just 1.14
    , pbo = Just 0.08
    , demoPeriodDays = 45
    }

testPromotionGate :: PromotionGate
testPromotionGate =
  PromotionGate
    { instrumentType = ETF
    , insiderRisk = Low
    , mnpiSelfDeclared = True
    , requiresComplianceReview = False
    , promotable = True
    }

activeEvaluation :: DemoRunEvaluation
activeEvaluation = startDemoRun testIdentifier testDemoRun startedAt testTrace

spec :: Spec
spec =
  describe "Domain.OrderExecution.DemoRunEvaluation" $ do
    -- Must-18: smart constructor
    describe "startDemoRun (Must-18)" $ do
      it "creates an Active, unpublished evaluation" $ do
        activeEvaluation.status `shouldBe` Active
        activeEvaluation.published `shouldBe` False
        activeEvaluation.identifier `shouldBe` testIdentifier
        activeEvaluation.demoRun `shouldBe` testDemoRun
        activeEvaluation.endedAt `shouldBe` Nothing

    -- Must-18 INV-EX-004 RULE-EX-007: complete once
    describe "completeDemoRun (INV-EX-004, RULE-EX-007)" $ do
      it "transitions Active -> Completed and stores metrics" $ do
        case completeDemoRun testPerformance testPromotionGate endedAt activeEvaluation of
          Left domainError -> error ("unexpected Left: " <> show domainError)
          Right (updated, _) -> do
            updated.status `shouldBe` Completed
            updated.endedAt `shouldBe` Just endedAt
            updated.performance `shouldBe` Just testPerformance
            updated.promotionGate `shouldBe` Just testPromotionGate

      it "emits DemoRunCompleted with identifier and trace (RULE-EX-008)" $ do
        case completeDemoRun testPerformance testPromotionGate endedAt activeEvaluation of
          Right (_, [event]) ->
            event
              `shouldBe` DemoRunCompleted
                { identifier = testIdentifier
                , demoRun = testDemoRun
                , trace = testTrace
                }
          other -> error ("unexpected: " <> show other)

      it "rejects a second completion (idempotent guard, INV-EX-004)" $ do
        case completeDemoRun testPerformance testPromotionGate endedAt activeEvaluation of
          Right (completed, _) ->
            completeDemoRun testPerformance testPromotionGate endedAt completed `shouldSatisfy` isLeft
          Left domainError -> error ("unexpected Left: " <> show domainError)

    -- Must-18: markPublished
    describe "markPublished (Must-18)" $ do
      it "sets published to True" $ do
        let published = markPublished activeEvaluation
        published.published `shouldBe` True

    -- Must-21: DemoRunCompletedSpecification
    describe "DemoRunCompletedSpecification.isDemoRunCompleted (Must-21)" $ do
      it "is not satisfied while still Active" $ do
        isDemoRunCompleted DemoRunCompletedSpecification activeEvaluation `shouldBe` False

      it "is satisfied when Completed and not yet published" $ do
        case completeDemoRun testPerformance testPromotionGate endedAt activeEvaluation of
          Right (completed, _) ->
            isDemoRunCompleted DemoRunCompletedSpecification completed `shouldBe` True
          Left domainError -> error ("unexpected Left: " <> show domainError)

      it "is not satisfied once published (no re-publish, INV-EX-004)" $ do
        case completeDemoRun testPerformance testPromotionGate endedAt activeEvaluation of
          Right (completed, _) ->
            isDemoRunCompleted DemoRunCompletedSpecification (markPublished completed) `shouldBe` False
          Left domainError -> error ("unexpected Left: " <> show domainError)

    -- Must-19: value objects
    describe "value objects (Must-19)" $ do
      it "InstrumentType distinguishes ETF and STOCK" $ do
        ETF `shouldBe` ETF
        (ETF == Stock) `shouldBe` False

      it "InsiderRisk has low/medium/high" $ do
        (Low == Medium) `shouldBe` False
        (Medium == High) `shouldBe` False
