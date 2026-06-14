module UseCase.CheckOrderRiskSpec (spec) where

import Control.Monad.State (State, get, modify, runState)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.RiskAssessment.Aggregate (
  OrderRiskAssessment,
  OrderRiskAssessmentIdentifier (..),
  OrderRiskAssessmentRepository (..),
  OrdersApprovedPayload,
  OrdersRejectedPayload,
  RiskEventPublisher (..),
 )
import Domain.RiskAssessment.Factory (OrdersProposedPayload (..))
import Domain.RiskAssessment.Port.IdempotencyKeyRepository (IdempotencyKeyRepository (..))
import Domain.RiskAssessment.ReasonCode (ReasonCode (..))
import Domain.RiskAssessment.ValueObjects (
  CompliancePolicy (..),
  RiskExposure (..),
  RiskLimits (..),
 )
import Test.Hspec (Spec, describe, it, shouldBe)
import UseCase.CheckOrderRisk (CheckOrderRiskResult (..), checkOrderRisk)

-- ---------------------------------------------------------------------
-- Test doubles (test-only, in test/ — not in src/)
-- ---------------------------------------------------------------------

-- | In-memory state for all ports in CheckOrderRisk tests.
data TestState = TestState
  { storedAssessments :: [OrderRiskAssessment]
  , processedKeys :: [(Text, Text)]
  , publishedApproved :: [OrdersApprovedPayload]
  , publishedRejected :: [OrdersRejectedPayload]
  }

emptyTestState :: TestState
emptyTestState =
  TestState
    { storedAssessments = []
    , processedKeys = []
    , publishedApproved = []
    , publishedRejected = []
    }

-- | Pure state monad carrying the TestState.
newtype TestMonad a = TestMonad (State TestState a)
  deriving newtype (Functor, Applicative, Monad)

instance OrderRiskAssessmentRepository TestMonad where
  find assessmentIdentifier = TestMonad $ do
    state <- get
    pure (findAssessment assessmentIdentifier state.storedAssessments)
  findByStatus status = TestMonad $ do
    state <- get
    pure (filter (\a -> a.orderStatus == status) state.storedAssessments)
  search _ = TestMonad $ do
    state <- get
    pure state.storedAssessments
  persist assessment =
    TestMonad $
      modify
        ( \state ->
            state
              { storedAssessments =
                  assessment
                    : filter (\a -> a.identifier /= assessment.identifier) state.storedAssessments
              }
        )
  terminate assessmentIdentifier =
    TestMonad $
      modify
        ( \state ->
            state
              { storedAssessments =
                  filter (\a -> a.identifier /= assessmentIdentifier) state.storedAssessments
              }
        )

instance IdempotencyKeyRepository TestMonad where
  find serviceId eventKey = TestMonad $ do
    state <- get
    pure ((serviceId, eventKey) `elem` state.processedKeys)
  persist serviceId eventKey =
    TestMonad $
      modify (\state -> state{processedKeys = (serviceId, eventKey) : state.processedKeys})
  terminate serviceId eventKey =
    TestMonad $
      modify
        ( \state ->
            state
              { processedKeys =
                  filter (\pair -> pair /= (serviceId, eventKey)) state.processedKeys
              }
        )

instance RiskEventPublisher TestMonad where
  publishOrdersApproved approvedPayload =
    TestMonad $
      modify (\state -> state{publishedApproved = approvedPayload : state.publishedApproved})
  publishOrdersRejected rejectedPayload =
    TestMonad $
      modify (\state -> state{publishedRejected = rejectedPayload : state.publishedRejected})

findAssessment :: OrderRiskAssessmentIdentifier -> [OrderRiskAssessment] -> Maybe OrderRiskAssessment
findAssessment identifier =
  List.find (\a -> a.identifier == identifier)

-- | Run the TestMonad and return both the result and the final state.
runTest :: TestMonad a -> TestState -> (a, TestState)
runTest (TestMonad action) = runState action

-- | Run the TestMonad with empty state and return both result and state.
runTestFromEmpty :: TestMonad a -> (a, TestState)
runTestFromEmpty action = runTest action emptyTestState

-- ---------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

defaultLimits :: RiskLimits
defaultLimits =
  RiskLimits
    { dailyLossLimit = 0.05
    , positionConcentrationLimit = 0.20
    , dailyOrderLimit = 50
    }

defaultExposure :: RiskExposure
defaultExposure =
  RiskExposure
    { dailyLossRate = 0.01
    , positionConcentrationRate = 0.05
    , dailyOrderCount = 5
    }

emptyPolicy :: CompliancePolicy
emptyPolicy =
  CompliancePolicy
    { restrictedSymbols = []
    , partnerRestrictedSymbols = []
    , blackoutWindows = []
    }

-- | A valid orders.proposed payload.
validPayload :: OrdersProposedPayload
validPayload =
  OrdersProposedPayload
    { identifier = mkULID 1
    , symbol = "7203.T"
    , side = "BUY"
    , qty = 100.0
    , trace = mkULID 100
    }

-- | A payload with an invalid side value.
invalidSidePayload :: OrdersProposedPayload
invalidSidePayload =
  validPayload{side = "INVALID"}

-- | A payload that will trigger kill switch rejection.
killSwitchPayload :: OrdersProposedPayload
killSwitchPayload = validPayload{identifier = mkULID 2}

-- ---------------------------------------------------------------------
-- TST-UC-001: happy path — persist and publish called once
-- ---------------------------------------------------------------------

spec :: Spec
spec = describe "UseCase.CheckOrderRisk" $ do
  describe "TST-UC-001: happy path — persist and publish once" $ do
    it "calls OrderRiskAssessmentRepository.persist exactly once" $ do
      let (_, finalState) =
            runTestFromEmpty
              (checkOrderRisk fixedTime False defaultLimits emptyPolicy defaultExposure validPayload)
      length finalState.storedAssessments `shouldBe` 1

    it "calls RiskEventPublisher.publishOrdersApproved exactly once" $ do
      let (_, finalState) =
            runTestFromEmpty
              (checkOrderRisk fixedTime False defaultLimits emptyPolicy defaultExposure validPayload)
      length finalState.publishedApproved `shouldBe` 1
      length finalState.publishedRejected `shouldBe` 0

    it "returns CheckOrderRiskApproved for valid order with no violations" $ do
      let (result, _) =
            runTestFromEmpty
              (checkOrderRisk fixedTime False defaultLimits emptyPolicy defaultExposure validPayload)
      result `shouldBe` CheckOrderRiskApproved

    it "records idempotency key after successful processing" $ do
      let (_, finalState) =
            runTestFromEmpty
              (checkOrderRisk fixedTime False defaultLimits emptyPolicy defaultExposure validPayload)
      length finalState.processedKeys `shouldBe` 1

  -- ---------------------------------------------------------------------
  -- TST-UC-002: duplicate event — no side effects
  -- ---------------------------------------------------------------------
  describe "TST-UC-002: duplicate event — no persist or publish" $ do
    let alreadyProcessedState =
          emptyTestState
            { processedKeys = [("risk-guard", Text.pack (show (mkULID 1)))]
            }

    it "returns CheckOrderRiskDuplicate when event already processed" $ do
      let (result, _) =
            runTest
              (checkOrderRisk fixedTime False defaultLimits emptyPolicy defaultExposure validPayload)
              alreadyProcessedState
      result `shouldBe` CheckOrderRiskDuplicate

    it "calls persist 0 times for duplicate event" $ do
      let (_, finalState) =
            runTest
              (checkOrderRisk fixedTime False defaultLimits emptyPolicy defaultExposure validPayload)
              alreadyProcessedState
      length finalState.storedAssessments `shouldBe` 0

    it "calls publish 0 times for duplicate event" $ do
      let (_, finalState) =
            runTest
              (checkOrderRisk fixedTime False defaultLimits emptyPolicy defaultExposure validPayload)
              alreadyProcessedState
      length finalState.publishedApproved `shouldBe` 0
      length finalState.publishedRejected `shouldBe` 0

  -- ---------------------------------------------------------------------
  -- TST-UC-003: factory failure — retryable = False
  -- ---------------------------------------------------------------------
  describe "TST-UC-003: factory failure — retryable = False" $ do
    it "returns CheckOrderRiskFailed with retryable=False when side is invalid" $ do
      let (result, _) =
            runTestFromEmpty
              (checkOrderRisk fixedTime False defaultLimits emptyPolicy defaultExposure invalidSidePayload)
      case result of
        CheckOrderRiskFailed _ retryable -> retryable `shouldBe` False
        other -> fail ("Expected CheckOrderRiskFailed but got: " ++ show other)

    it "does not call persist when factory fails" $ do
      let (_, finalState) =
            runTestFromEmpty
              (checkOrderRisk fixedTime False defaultLimits emptyPolicy defaultExposure invalidSidePayload)
      length finalState.storedAssessments `shouldBe` 0

    it "does not call publish when factory fails" $ do
      let (_, finalState) =
            runTestFromEmpty
              (checkOrderRisk fixedTime False defaultLimits emptyPolicy defaultExposure invalidSidePayload)
      length finalState.publishedApproved `shouldBe` 0
      length finalState.publishedRejected `shouldBe` 0

  -- ---------------------------------------------------------------------
  -- TST-UC-004: kill switch enabled — rejected, publishOrdersRejected called
  -- ---------------------------------------------------------------------
  describe "TST-UC-004: kill switch enabled — rejected" $ do
    it "returns CheckOrderRiskRejected KillSwitchEnabled when kill switch is on" $ do
      let (result, _) =
            runTestFromEmpty
              (checkOrderRisk fixedTime True defaultLimits emptyPolicy defaultExposure killSwitchPayload)
      result `shouldBe` CheckOrderRiskRejected KillSwitchEnabled

    it "calls publishOrdersRejected exactly once when kill switch rejects" $ do
      let (_, finalState) =
            runTestFromEmpty
              (checkOrderRisk fixedTime True defaultLimits emptyPolicy defaultExposure killSwitchPayload)
      length finalState.publishedRejected `shouldBe` 1
      length finalState.publishedApproved `shouldBe` 0

    it "persists the rejected assessment" $ do
      let (_, finalState) =
            runTestFromEmpty
              (checkOrderRisk fixedTime True defaultLimits emptyPolicy defaultExposure killSwitchPayload)
      length finalState.storedAssessments `shouldBe` 1
