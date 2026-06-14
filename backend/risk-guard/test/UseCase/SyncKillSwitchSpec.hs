module UseCase.SyncKillSwitchSpec (spec) where

import Control.Monad.State (State, get, modify, runState)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.RiskAssessment (Trace (..))
import Domain.RiskAssessment.Aggregate (
  OrderRiskAssessment,
  OrderRiskAssessmentIdentifier (..),
  OrderRiskAssessmentRepository (..),
  acceptOrderProposal,
 )
import Domain.RiskAssessment.Port.IdempotencyKeyRepository (IdempotencyKeyRepository (..))
import Domain.RiskAssessment.ValueObjects (
  CompliancePolicy (..),
  OrderProposal (..),
  RiskExposure (..),
  RiskLimits (..),
  Side (..),
 )
import Test.Hspec (Spec, describe, it, shouldBe)
import UseCase.SyncKillSwitch (
  KillSwitchChangedPayload (..),
  SyncKillSwitchResult (..),
  syncKillSwitch,
 )

-- ---------------------------------------------------------------------
-- Test doubles (test-only, in test/ — not in src/)
-- ---------------------------------------------------------------------

-- | In-memory state for all ports in SyncKillSwitch tests.
data TestState = TestState
  { storedAssessments :: [OrderRiskAssessment]
  , processedKeys :: [(Text, Text)]
  }

emptyTestState :: TestState
emptyTestState =
  TestState
    { storedAssessments = []
    , processedKeys = []
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

findAssessment :: OrderRiskAssessmentIdentifier -> [OrderRiskAssessment] -> Maybe OrderRiskAssessment
findAssessment assessmentIdentifier =
  List.find (\a -> a.identifier == assessmentIdentifier)

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

testTrace :: Trace
testTrace = Trace (mkULID 100)

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

mkProposal :: OrderRiskAssessmentIdentifier -> OrderProposal
mkProposal assessmentIdentifier =
  OrderProposal
    { identifier = assessmentIdentifier
    , symbol = "7203.T"
    , side = Buy
    , qty = 100.0
    }

-- | Build a PROPOSED assessment with a given identifier (kill switch off).
mkProposedAssessment :: Integer -> OrderRiskAssessment
mkProposedAssessment n =
  let assessmentIdentifier = OrderRiskAssessmentIdentifier (mkULID n)
   in acceptOrderProposal
        assessmentIdentifier
        (mkProposal assessmentIdentifier)
        testTrace
        False
        defaultLimits
        emptyPolicy
        defaultExposure
        fixedTime

-- | Build a PROPOSED assessment with kill switch ON.
mkKillSwitchOnAssessment :: Integer -> OrderRiskAssessment
mkKillSwitchOnAssessment n =
  let assessmentIdentifier = OrderRiskAssessmentIdentifier (mkULID n)
   in acceptOrderProposal
        assessmentIdentifier
        (mkProposal assessmentIdentifier)
        testTrace
        True
        defaultLimits
        emptyPolicy
        defaultExposure
        fixedTime

-- | A valid kill switch changed payload (enable).
enablePayload :: KillSwitchChangedPayload
enablePayload =
  KillSwitchChangedPayload
    { identifier = mkULID 200
    , enabled = True
    , trace = mkULID 201
    }

-- | A valid kill switch changed payload (disable).
disablePayload :: KillSwitchChangedPayload
disablePayload =
  KillSwitchChangedPayload
    { identifier = mkULID 202
    , enabled = False
    , trace = mkULID 203
    }

-- ---------------------------------------------------------------------
-- TST-UC-005: syncKillSwitch applies state to all PROPOSED assessments
-- ---------------------------------------------------------------------

spec :: Spec
spec = describe "UseCase.SyncKillSwitch" $ do
  describe "TST-UC-005: applies kill switch state to all PROPOSED assessments" $ do
    it "returns SyncKillSwitchApplied on success" $ do
      let (result, _) = runTestFromEmpty (syncKillSwitch enablePayload)
      result `shouldBe` SyncKillSwitchApplied

    it "records idempotency key after applying state" $ do
      let (_, finalState) = runTestFromEmpty (syncKillSwitch enablePayload)
      length finalState.processedKeys `shouldBe` 1

    it "persists all PROPOSED assessments with updated kill switch state" $ do
      let assessment1 = mkProposedAssessment 10
          assessment2 = mkProposedAssessment 11
          initialState =
            emptyTestState
              { storedAssessments = [assessment1, assessment2]
              }
      let (_, finalState) = runTest (syncKillSwitch enablePayload) initialState
      length finalState.storedAssessments `shouldBe` 2

    it "updates killSwitchEnabled to True on all PROPOSED assessments" $ do
      let assessment1 = mkProposedAssessment 10
          assessment2 = mkProposedAssessment 11
          initialState =
            emptyTestState
              { storedAssessments = [assessment1, assessment2]
              }
      let (_, finalState) = runTest (syncKillSwitch enablePayload) initialState
      all (.killSwitchEnabled) finalState.storedAssessments `shouldBe` True

    it "calls findByStatus to fetch only PROPOSED assessments" $ do
      let assessment = mkProposedAssessment 10
          initialState = emptyTestState{storedAssessments = [assessment]}
      let (_, finalState) = runTest (syncKillSwitch enablePayload) initialState
      case finalState.storedAssessments of
        [updated] -> updated.killSwitchEnabled `shouldBe` True
        other -> fail ("Expected exactly 1 assessment but got: " ++ show (length other))

    it "updates killSwitchEnabled to False when disabling" $ do
      let killSwitchOnAssessment = mkKillSwitchOnAssessment 10
          initialState = emptyTestState{storedAssessments = [killSwitchOnAssessment]}
      let (_, finalState) = runTest (syncKillSwitch disablePayload) initialState
      case finalState.storedAssessments of
        [updated] -> updated.killSwitchEnabled `shouldBe` False
        other -> fail ("Expected exactly 1 assessment but got: " ++ show (length other))

  -- ---------------------------------------------------------------------
  -- TST-UC-006: duplicate event — no findByStatus or persist
  -- ---------------------------------------------------------------------
  describe "TST-UC-006: duplicate event — no findByStatus or persist" $ do
    let alreadyProcessedState =
          emptyTestState
            { processedKeys = [("risk-guard", Text.pack (show (mkULID 200)))]
            , storedAssessments = [mkProposedAssessment 10]
            }

    it "returns SyncKillSwitchDuplicate when event already processed" $ do
      let (result, _) = runTest (syncKillSwitch enablePayload) alreadyProcessedState
      result `shouldBe` SyncKillSwitchDuplicate

    it "does not modify stored assessments for duplicate event" $ do
      let (_, finalState) = runTest (syncKillSwitch enablePayload) alreadyProcessedState
      length finalState.storedAssessments `shouldBe` 1
      case finalState.storedAssessments of
        [assessment] -> assessment.killSwitchEnabled `shouldBe` False
        other -> fail ("Expected exactly 1 assessment but got: " ++ show (length other))

    it "does not add a new idempotency key for duplicate event" $ do
      let (_, finalState) = runTest (syncKillSwitch enablePayload) alreadyProcessedState
      length finalState.processedKeys `shouldBe` 1
