module Domain.OrderProposal.Factory.ProposalDispatchFactorySpec (spec) where

import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Factory.ProposalDispatchFactory (fromSignalGeneratedEvent)
import Domain.OrderProposal.ProposalDispatch (
  DispatchStatus (..),
  ProposalDispatchIdentifier (..),
 )
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

-- ---------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "Domain.OrderProposal.Factory.ProposalDispatchFactory" $ do
    describe "fromSignalGeneratedEvent (MUST-25)" $ do
      it "MUST-25: sets identifier from input event identifier" $ do
        let (dispatch, _) = fromSignalGeneratedEvent testDispatchIdentifier validSignalSnapshot testTrace
        dispatch.identifier `shouldBe` testDispatchIdentifier

      it "MUST-25: sets initial dispatchStatus to Pending" $ do
        let (dispatch, _) = fromSignalGeneratedEvent testDispatchIdentifier validSignalSnapshot testTrace
        dispatch.dispatchStatus `shouldBe` Pending

      it "sets orders to empty list initially" $ do
        let (dispatch, _) = fromSignalGeneratedEvent testDispatchIdentifier validSignalSnapshot testTrace
        dispatch.orders `shouldBe` []

      it "sets orderCount to Nothing initially" $ do
        let (dispatch, _) = fromSignalGeneratedEvent testDispatchIdentifier validSignalSnapshot testTrace
        dispatch.orderCount `shouldBe` Nothing

      it "stores the signal snapshot" $ do
        let (dispatch, _) = fromSignalGeneratedEvent testDispatchIdentifier validSignalSnapshot testTrace
        dispatch.signalSnapshot `shouldBe` validSignalSnapshot
