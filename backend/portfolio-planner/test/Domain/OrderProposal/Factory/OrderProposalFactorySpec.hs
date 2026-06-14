module Domain.OrderProposal.Factory.OrderProposalFactorySpec (spec) where

import Data.Either (isLeft)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Aggregate (
  OrderProposalIdentifier (..),
  OrderStatus (..),
  Side (..),
 )
import Domain.OrderProposal.Factory.OrderProposalFactory (fromSignalSnapshot)
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

-- ---------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "Domain.OrderProposal.Factory.OrderProposalFactory" $ do
    describe "fromSignalSnapshot (MUST-24)" $ do
      it "MUST-24: success case produces status == Proposed (INV-PP-001)" $ do
        case fromSignalSnapshot testIdentifier "7203" Buy 500 validSignalSnapshot validStrategySnapshot testTrace fixedTime of
          Left domainError -> expectationFailure ("Unexpected Left: " ++ show domainError)
          Right (proposal, _) ->
            proposal.status `shouldBe` Proposed

      it "MUST-24: sets identifier from input" $ do
        case fromSignalSnapshot testIdentifier "7203" Buy 500 validSignalSnapshot validStrategySnapshot testTrace fixedTime of
          Left domainError -> expectationFailure ("Unexpected Left: " ++ show domainError)
          Right (proposal, _) ->
            proposal.identifier `shouldBe` testIdentifier

      it "MUST-24: sets symbol and side correctly" $ do
        case fromSignalSnapshot testIdentifier "7203" Sell 200 validSignalSnapshot validStrategySnapshot testTrace fixedTime of
          Left domainError -> expectationFailure ("Unexpected Left: " ++ show domainError)
          Right (proposal, _) -> do
            proposal.symbol `shouldBe` "7203"
            proposal.side `shouldBe` Sell

      it "MUST-24: rejects qty <= 0 (INV-PP-002)" $ do
        fromSignalSnapshot testIdentifier "7203" Buy 0 validSignalSnapshot validStrategySnapshot testTrace fixedTime
          `shouldSatisfy` isLeft

      it "MUST-24: rejects negative qty (INV-PP-002)" $ do
        fromSignalSnapshot testIdentifier "7203" Buy (-1) validSignalSnapshot validStrategySnapshot testTrace fixedTime
          `shouldSatisfy` isLeft

      it "emits OrderProposalCreated event" $ do
        case fromSignalSnapshot testIdentifier "7203" Buy 500 validSignalSnapshot validStrategySnapshot testTrace fixedTime of
          Left domainError -> expectationFailure ("Unexpected Left: " ++ show domainError)
          Right (_, events) ->
            length events `shouldBe` 1
