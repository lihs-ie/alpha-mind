module UseCase.PortfolioPlanningServiceSpec (spec) where

import Control.Monad.State.Strict (State, execState, gets, modify, runState)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Aggregate (
  OrderProposal,
  OrderProposalIdentifier (..),
  OrderProposalSearchCriteria,
  OrderStatus,
  Side (..),
 )
import Domain.OrderProposal.Ports (
  IdempotencyKeyRepository (..),
  OrderProposalRepository (..),
  ProposalDispatchRepository (..),
 )
import Domain.OrderProposal.ProposalDispatch (
  ProposalDispatch,
  ProposalDispatchIdentifier (..),
  startDispatch,
 )
import Domain.OrderProposal.ReasonCode (ReasonCode (..))
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
  StrategySnapshot (..),
 )
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldSatisfy)
import UseCase.PortfolioPlanningService (
  ProposeOrdersInput (..),
  ProposeOrdersResult (..),
  proposeOrders,
 )

-- ---------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

testTrace :: Trace
testTrace = Trace (mkULID 100)

testDispatchIdentifier :: ProposalDispatchIdentifier
testDispatchIdentifier = ProposalDispatchIdentifier (mkULID 1)

testOrderProposalIdentifier :: OrderProposalIdentifier
testOrderProposalIdentifier = OrderProposalIdentifier (mkULID 2)

validSignalSnapshot :: SignalSnapshot
validSignalSnapshot =
  SignalSnapshot
    { signalVersion = "v1.0"
    , modelVersion = "m2.0"
    , featureVersion = "f3.0"
    , storagePath = "gs://bucket/signals/2026-01-15.parquet"
    , degradationFlag = Normal
    , requiresComplianceReview = False
    }

complianceSignalSnapshot :: SignalSnapshot
complianceSignalSnapshot = validSignalSnapshot{requiresComplianceReview = True}

missingFieldSignalSnapshot :: SignalSnapshot
missingFieldSignalSnapshot = validSignalSnapshot{signalVersion = ""}

validStrategySnapshot :: StrategySnapshot
validStrategySnapshot =
  StrategySnapshot
    { maxOrderCount = 10
    , maxSingleOrderQty = 1000
    , rebalanceThreshold = 0.05
    }

validInput :: ProposeOrdersInput
validInput =
  ProposeOrdersInput
    { eventIdentifier = testDispatchIdentifier
    , orderProposalIdentifier = testOrderProposalIdentifier
    , signalSnapshot = validSignalSnapshot
    , strategySnapshot = validStrategySnapshot
    , proposalSymbol = "7203"
    , proposalSide = Buy
    , trace = testTrace
    }

-- ---------------------------------------------------------------------
-- Test monad: State-based in-memory repositories
-- ---------------------------------------------------------------------

data TestRepositoryState = TestRepositoryState
  { persistedOrderProposals :: Map OrderProposalIdentifier OrderProposal
  , persistedDispatches :: Map ProposalDispatchIdentifier ProposalDispatch
  , idempotencyKeys :: Map ProposalDispatchIdentifier ProposalDispatch
  , persistOrderProposalCallCount :: Int
  , persistProposalDispatchCallCount :: Int
  , persistIdempotencyKeyCallCount :: Int
  }

emptyTestRepositoryState :: TestRepositoryState
emptyTestRepositoryState =
  TestRepositoryState
    { persistedOrderProposals = Map.empty
    , persistedDispatches = Map.empty
    , idempotencyKeys = Map.empty
    , persistOrderProposalCallCount = 0
    , persistProposalDispatchCallCount = 0
    , persistIdempotencyKeyCallCount = 0
    }

newtype TestMonad a = TestMonad {runTestMonad :: State TestRepositoryState a}
  deriving newtype (Functor, Applicative, Monad)

instance OrderProposalRepository TestMonad where
  findOrderProposal inputIdentifier = TestMonad $ do
    proposals <- gets persistedOrderProposals
    pure (Map.lookup inputIdentifier proposals)
  findOrderProposalsByStatus inputStatus = TestMonad $ do
    proposals <- gets persistedOrderProposals
    pure [p | p <- Map.elems proposals, p.status == inputStatus]
  searchOrderProposals _ = TestMonad (pure [])
  persistOrderProposal proposal =
    TestMonad $
      modify
        ( \s ->
            s
              { persistedOrderProposals =
                  Map.insert proposal.identifier proposal s.persistedOrderProposals
              , persistOrderProposalCallCount = s.persistOrderProposalCallCount + 1
              }
        )
  terminateOrderProposal _ = TestMonad (pure ())

instance ProposalDispatchRepository TestMonad where
  findProposalDispatch inputIdentifier = TestMonad $ do
    dispatches <- gets persistedDispatches
    pure (Map.lookup inputIdentifier dispatches)
  persistProposalDispatch dispatch =
    TestMonad $
      modify
        ( \s ->
            s
              { persistedDispatches =
                  Map.insert dispatch.identifier dispatch s.persistedDispatches
              , persistProposalDispatchCallCount = s.persistProposalDispatchCallCount + 1
              }
        )
  terminateProposalDispatch _ = TestMonad (pure ())

instance IdempotencyKeyRepository TestMonad where
  findIdempotencyKey inputIdentifier = TestMonad $ do
    keys <- gets idempotencyKeys
    pure (Map.lookup inputIdentifier keys)
  persistIdempotencyKey dispatch =
    TestMonad $
      modify
        ( \s ->
            s
              { idempotencyKeys =
                  Map.insert dispatch.identifier dispatch s.idempotencyKeys
              , persistIdempotencyKeyCallCount = s.persistIdempotencyKeyCallCount + 1
              }
        )
  terminateIdempotencyKey _ = TestMonad (pure ())

runTest :: TestMonad a -> TestRepositoryState -> (a, TestRepositoryState)
runTest action = runState (runTestMonad action)

execTest :: TestMonad a -> TestRepositoryState -> TestRepositoryState
execTest action = execState (runTestMonad action)

-- | State with a pre-seeded idempotency key for testDispatchIdentifier.
stateWithExistingKey :: TestRepositoryState
stateWithExistingKey =
  let seededDispatch = fst (startDispatch testDispatchIdentifier validSignalSnapshot testTrace)
      keys = Map.singleton testDispatchIdentifier seededDispatch
   in emptyTestRepositoryState{idempotencyKeys = keys}

-- Silence unused-import warning for OrderProposalSearchCriteria
_usedForTypes :: OrderProposalSearchCriteria
_usedForTypes = error "phantom"

-- Silence unused-import warning for OrderStatus
_usedForOrderStatus :: OrderStatus
_usedForOrderStatus = error "phantom"

-- ---------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "UseCase.PortfolioPlanningService" $ do
    -- MUST-03: Idempotency duplicate path
    describe "proposeOrders — idempotency duplicate path (MUST-03)" $ do
      it "returns ProposeOrdersDuplicate when event identifier already processed" $ do
        let (result, _) = runTest (proposeOrders fixedTime validInput) stateWithExistingKey
        case result of
          ProposeOrdersDuplicate -> pure ()
          other -> expectationFailure ("Expected ProposeOrdersDuplicate, got: " ++ show other)

      it "does NOT call persistOrderProposal when duplicate (MUST-03)" $ do
        let finalState = execTest (proposeOrders fixedTime validInput) stateWithExistingKey
        finalState.persistOrderProposalCallCount `shouldBe` 0

      it "does NOT call persistProposalDispatch when duplicate (MUST-03)" $ do
        let finalState = execTest (proposeOrders fixedTime validInput) stateWithExistingKey
        finalState.persistProposalDispatchCallCount `shouldBe` 0

    -- MUST-05 / RULE-PP-002: Compliance failure path
    describe "proposeOrders — compliance review required path (MUST-05, RULE-PP-002)" $ do
      it "returns ProposeOrdersFailed with ComplianceReviewRequired when requiresComplianceReview=true" $ do
        let input = validInput{signalSnapshot = complianceSignalSnapshot}
        let (result, _) = runTest (proposeOrders fixedTime input) emptyTestRepositoryState
        case result of
          ProposeOrdersFailed{reasonCode = ComplianceReviewRequired} -> pure ()
          other ->
            expectationFailure
              ("Expected ProposeOrdersFailed ComplianceReviewRequired, got: " ++ show other)

      it "does NOT call persistOrderProposal on compliance failure (MUST-05)" $ do
        let input = validInput{signalSnapshot = complianceSignalSnapshot}
        let finalState = execTest (proposeOrders fixedTime input) emptyTestRepositoryState
        finalState.persistOrderProposalCallCount `shouldBe` 0

    -- MUST-05 / RULE-PP-001: Missing required fields path
    describe "proposeOrders — missing required fields path (MUST-05, RULE-PP-001)" $ do
      it "returns ProposeOrdersFailed when signalVersion is empty" $ do
        let input = validInput{signalSnapshot = missingFieldSignalSnapshot}
        let (result, _) = runTest (proposeOrders fixedTime input) emptyTestRepositoryState
        case result of
          ProposeOrdersFailed{} -> pure ()
          other -> expectationFailure ("Expected ProposeOrdersFailed, got: " ++ show other)

      it "does NOT call persistOrderProposal on missing fields failure (MUST-05)" $ do
        let input = validInput{signalSnapshot = missingFieldSignalSnapshot}
        let finalState = execTest (proposeOrders fixedTime input) emptyTestRepositoryState
        finalState.persistOrderProposalCallCount `shouldBe` 0

    -- MUST-07: Happy path — orders proposed
    describe "proposeOrders — successful proposal path (MUST-07)" $ do
      it "returns ProposeOrdersSucceeded with orders" $ do
        let (result, _) = runTest (proposeOrders fixedTime validInput) emptyTestRepositoryState
        case result of
          ProposeOrdersSucceeded{} -> pure ()
          other -> expectationFailure ("Expected ProposeOrdersSucceeded, got: " ++ show other)

      it "calls persistOrderProposal at least once on success (MUST-07)" $ do
        let finalState = execTest (proposeOrders fixedTime validInput) emptyTestRepositoryState
        finalState.persistOrderProposalCallCount `shouldSatisfy` (>= 1)

      it "persisted order count matches orders in result (MUST-09)" $ do
        let (result, finalState) = runTest (proposeOrders fixedTime validInput) emptyTestRepositoryState
        case result of
          ProposeOrdersSucceeded{orders = oids} ->
            length oids `shouldBe` finalState.persistOrderProposalCallCount
          other -> expectationFailure ("Expected ProposeOrdersSucceeded, got: " ++ show other)

      -- MUST-08: trace and identifier in result
      it "result contains the input trace (MUST-08)" $ do
        let (result, _) = runTest (proposeOrders fixedTime validInput) emptyTestRepositoryState
        case result of
          ProposeOrdersSucceeded{trace = t} -> t `shouldBe` testTrace
          other -> expectationFailure ("Expected ProposeOrdersSucceeded, got: " ++ show other)

      it "result contains the input eventIdentifier as dispatch (MUST-08)" $ do
        let (result, _) = runTest (proposeOrders fixedTime validInput) emptyTestRepositoryState
        case result of
          ProposeOrdersSucceeded{dispatch = dIdentifier} ->
            dIdentifier `shouldBe` testDispatchIdentifier
          other -> expectationFailure ("Expected ProposeOrdersSucceeded, got: " ++ show other)

      -- MUST-04: persistIdempotencyKey called on success
      it "calls persistIdempotencyKey exactly once on success (MUST-04)" $ do
        let finalState = execTest (proposeOrders fixedTime validInput) emptyTestRepositoryState
        finalState.persistIdempotencyKeyCallCount `shouldBe` 1

    -- MUST-04: Second call with same identifier is idempotent
    describe "proposeOrders — second call idempotency (MUST-03, MUST-04)" $ do
      it "second call with same identifier returns ProposeOrdersDuplicate" $ do
        let (_, firstState) = runTest (proposeOrders fixedTime validInput) emptyTestRepositoryState
        let (result, _) = runTest (proposeOrders fixedTime validInput) firstState
        case result of
          ProposeOrdersDuplicate -> pure ()
          other ->
            expectationFailure ("Expected ProposeOrdersDuplicate on second call, got: " ++ show other)

      it "second call does NOT add more persisted orders" $ do
        let (_, firstState) = runTest (proposeOrders fixedTime validInput) emptyTestRepositoryState
        let (_, secondState) = runTest (proposeOrders fixedTime validInput) firstState
        secondState.persistOrderProposalCallCount `shouldBe` firstState.persistOrderProposalCallCount

    -- MUST-09: orderCount in dispatch matches persisted order count
    describe "proposeOrders — orderCount consistency (MUST-09)" $ do
      it "completed dispatch orderCount equals number of persisted OrderProposals" $ do
        let (_, finalState) = runTest (proposeOrders fixedTime validInput) emptyTestRepositoryState
        let orderCount = Map.size finalState.persistedOrderProposals
        case Map.lookup testDispatchIdentifier finalState.persistedDispatches of
          Nothing -> expectationFailure "Expected dispatch to be persisted"
          Just dispatch ->
            case dispatch.orderCount of
              Nothing -> expectationFailure "Expected dispatch to have orderCount set after completion"
              Just count -> count `shouldBe` orderCount

    -- MUST-08: trace in failure result
    describe "proposeOrders — trace in failure result (MUST-08)" $ do
      it "failure result contains the input trace" $ do
        let input = validInput{signalSnapshot = complianceSignalSnapshot}
        let (result, _) = runTest (proposeOrders fixedTime input) emptyTestRepositoryState
        case result of
          ProposeOrdersFailed{trace = t} -> t `shouldBe` testTrace
          other -> expectationFailure ("Expected ProposeOrdersFailed, got: " ++ show other)
