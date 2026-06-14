module Domain.OrderProposal.AggregateSpec (spec) where

import Data.Either (isLeft, isRight)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Aggregate (
  OrderProposal,
  OrderProposalEvent (..),
  OrderProposalIdentifier (..),
  OrderStatus (..),
  Side (..),
  approveProposal,
  createProposal,
  markExecuted,
  markFailed,
  rejectProposal,
 )
import Domain.OrderProposal.Error (DomainError)
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
  StrategySnapshot (..),
 )
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

testIdentifier :: OrderProposalIdentifier
testIdentifier = OrderProposalIdentifier (mkULID 1)

testTrace :: Trace
testTrace = Trace (mkULID 100)

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

validStrategySnapshot :: StrategySnapshot
validStrategySnapshot =
  StrategySnapshot
    { maxOrderCount = 10
    , maxSingleOrderQty = 1000
    , rebalanceThreshold = 0.05
    }

mkValidProposal :: Either DomainError (OrderProposal, [OrderProposalEvent])
mkValidProposal =
  createProposal
    testIdentifier
    "7203"
    Buy
    500
    validSignalSnapshot
    Nothing
    validStrategySnapshot
    testTrace
    fixedTime

-- ---------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "Domain.OrderProposal.Aggregate" $ do
    -- MUST-09, MUST-10: createProposal invariants
    describe "createProposal (MUST-09, MUST-10)" $ do
      it "MUST-09: sets status to Proposed on success (INV-PP-001)" $ do
        case mkValidProposal of
          Left err -> expectationFailure ("Unexpected Left: " ++ show err)
          Right (proposal, _) ->
            proposal.status `shouldBe` Proposed

      it "MUST-09: identifier matches input" $ do
        case mkValidProposal of
          Left err -> expectationFailure ("Unexpected Left: " ++ show err)
          Right (proposal, _) ->
            proposal.identifier `shouldBe` testIdentifier

      it "MUST-10: rejects qty == 0 (INV-PP-002)" $ do
        createProposal testIdentifier "7203" Buy 0 validSignalSnapshot Nothing validStrategySnapshot testTrace fixedTime
          `shouldSatisfy` isLeft

      it "MUST-10: rejects qty < 0 (INV-PP-002)" $ do
        createProposal testIdentifier "7203" Buy (-100) validSignalSnapshot Nothing validStrategySnapshot testTrace fixedTime
          `shouldSatisfy` isLeft

      it "accepts positive qty" $ do
        createProposal testIdentifier "7203" Buy 1 validSignalSnapshot Nothing validStrategySnapshot testTrace fixedTime
          `shouldSatisfy` isRight

      it "emits OrderProposalCreated event with trace" $ do
        case mkValidProposal of
          Left err -> expectationFailure ("Unexpected Left: " ++ show err)
          Right (_, [OrderProposalCreated{trace = t}]) ->
            t `shouldBe` testTrace
          Right (_, events) ->
            expectationFailure ("Expected 1 event, got " ++ show (length events))

    -- State transition tests
    describe "rejectProposal" $ do
      it "transitions Proposed → Rejected" $ do
        case mkValidProposal of
          Left err -> expectationFailure ("Unexpected Left: " ++ show err)
          Right (proposal, _) ->
            case rejectProposal proposal of
              Left err -> expectationFailure ("Unexpected Left: " ++ show err)
              Right updated -> updated.status `shouldBe` Rejected

      it "rejects non-Proposed status" $ do
        case mkValidProposal of
          Left err -> expectationFailure ("Unexpected Left: " ++ show err)
          Right (proposal, _) ->
            case rejectProposal proposal of
              Left err -> expectationFailure ("Unexpected Left: " ++ show err)
              Right rejected ->
                rejectProposal rejected `shouldSatisfy` isLeft

    describe "approveProposal" $ do
      it "transitions Proposed → Approved" $ do
        case mkValidProposal of
          Left err -> expectationFailure ("Unexpected Left: " ++ show err)
          Right (proposal, _) ->
            case approveProposal proposal of
              Left err -> expectationFailure ("Unexpected Left: " ++ show err)
              Right updated -> updated.status `shouldBe` Approved

    describe "markExecuted" $ do
      it "transitions Approved → Executed" $ do
        case mkValidProposal of
          Left err -> expectationFailure ("Unexpected Left: " ++ show err)
          Right (proposal, _) ->
            case approveProposal proposal of
              Left err -> expectationFailure ("Unexpected Left: " ++ show err)
              Right approved ->
                case markExecuted approved of
                  Left err -> expectationFailure ("Unexpected Left: " ++ show err)
                  Right updated -> updated.status `shouldBe` Executed

      it "rejects Proposed status" $ do
        case mkValidProposal of
          Left err -> expectationFailure ("Unexpected Left: " ++ show err)
          Right (proposal, _) ->
            markExecuted proposal `shouldSatisfy` isLeft

    describe "markFailed" $ do
      it "transitions Approved → Failed" $ do
        case mkValidProposal of
          Left err -> expectationFailure ("Unexpected Left: " ++ show err)
          Right (proposal, _) ->
            case approveProposal proposal of
              Left err -> expectationFailure ("Unexpected Left: " ++ show err)
              Right approved ->
                case markFailed approved of
                  Left err -> expectationFailure ("Unexpected Left: " ++ show err)
                  Right updated -> updated.status `shouldBe` Failed

    -- MUST-29: naming convention
    describe "identifier naming (MUST-29)" $ do
      it "uses 'identifier' field, not 'id'" $ do
        case mkValidProposal of
          Left err -> expectationFailure ("Unexpected Left: " ++ show err)
          Right (proposal, _) ->
            -- Compiles only if .identifier accessor exists (not .id or .orderId)
            proposal.identifier `shouldBe` testIdentifier
