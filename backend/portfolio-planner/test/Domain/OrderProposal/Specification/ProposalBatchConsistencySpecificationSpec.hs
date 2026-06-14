module Domain.OrderProposal.Specification.ProposalBatchConsistencySpecificationSpec (spec) where

import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Aggregate (OrderProposalIdentifier (..))
import Domain.OrderProposal.Error (DomainError (..))
import Domain.OrderProposal.ProposalDispatch (
  ProposalDispatch,
  ProposalDispatchEvent,
  ProposalDispatchIdentifier (..),
  completeDispatch,
  startDispatch,
 )
import Domain.OrderProposal.Specification.ProposalBatchConsistencySpecification (isSatisfiedBy)
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
 )
import Test.Hspec (Spec, describe, it, shouldBe)

-- ---------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

testDispatchIdentifier :: ProposalDispatchIdentifier
testDispatchIdentifier = ProposalDispatchIdentifier (mkULID 200)

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

testOrderIdentifiers :: [OrderProposalIdentifier]
testOrderIdentifiers =
  [ OrderProposalIdentifier (mkULID 301)
  , OrderProposalIdentifier (mkULID 302)
  ]

mkPendingDispatch :: (ProposalDispatch, [ProposalDispatchEvent])
mkPendingDispatch = startDispatch testDispatchIdentifier validSignalSnapshot testTrace

-- | Produce a Completed dispatch with consistent orderCount == length orders.
mkCompletedDispatch :: ProposalDispatch
mkCompletedDispatch =
  let (dispatch, _) = mkPendingDispatch
      count = length testOrderIdentifiers
   in case completeDispatch count testOrderIdentifiers fixedTime dispatch of
        Left domainError -> error ("Test setup failed: " ++ show domainError)
        Right (completed, _) -> completed

-- ---------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "Domain.OrderProposal.Specification.ProposalBatchConsistencySpecification" $ do
    describe "isSatisfiedBy (MUST-19)" $ do
      it "returns True for Pending dispatch" $ do
        let (dispatch, _) = mkPendingDispatch
        isSatisfiedBy dispatch `shouldBe` True

      it "MUST-19: returns True for Completed dispatch where orderCount == length orders" $ do
        isSatisfiedBy mkCompletedDispatch `shouldBe` True

      it "MUST-19: the completeDispatch command enforces the invariant (INV-PP-004)" $ do
        -- This test verifies that a dispatch where the count does NOT match
        -- cannot be created through normal commands — completeDispatch returns Left.
        let (dispatch, _) = mkPendingDispatch
        let mismatchedCount = length testOrderIdentifiers + 1
        let result = completeDispatch mismatchedCount testOrderIdentifiers fixedTime dispatch
        -- The command itself rejects the mismatched count
        result
          `shouldBe` Left
            ( InvariantViolation
                "ProposalDispatch"
                "orderCount must equal length of orders (INV-PP-004)"
            )
