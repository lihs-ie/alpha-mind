module Domain.OrderProposal.ProposalDispatchSpec (spec) where

import Data.Either (isLeft, isRight)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Aggregate (OrderProposalIdentifier (..))
import Domain.OrderProposal.ProposalDispatch (
  DispatchStatus (..),
  ProposalDispatch,
  ProposalDispatchEvent (..),
  ProposalDispatchIdentifier (..),
  completeDispatch,
  failDispatch,
  startDispatch,
 )
import Domain.OrderProposal.ReasonCode (ReasonCode (..))
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
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

mkPendingDispatch :: (ProposalDispatch, [ProposalDispatchEvent])
mkPendingDispatch = startDispatch testDispatchIdentifier validSignalSnapshot testTrace

testOrderIdentifiers :: [OrderProposalIdentifier]
testOrderIdentifiers =
  [ OrderProposalIdentifier (mkULID 301)
  , OrderProposalIdentifier (mkULID 302)
  ]

-- ---------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "Domain.OrderProposal.ProposalDispatch" $ do
    describe "startDispatch" $ do
      it "sets dispatchStatus to Pending" $ do
        let (dispatch, _) = mkPendingDispatch
        dispatch.dispatchStatus `shouldBe` Pending

      it "sets identifier to input identifier" $ do
        let (dispatch, _) = mkPendingDispatch
        dispatch.identifier `shouldBe` testDispatchIdentifier

      it "sets orders to empty list" $ do
        let (dispatch, _) = mkPendingDispatch
        dispatch.orders `shouldBe` []

      it "sets orderCount to Nothing" $ do
        let (dispatch, _) = mkPendingDispatch
        dispatch.orderCount `shouldBe` Nothing

    -- MUST-11: completeDispatch invariant (INV-PP-004)
    describe "completeDispatch (MUST-11, INV-PP-004)" $ do
      it "transitions Pending → Completed when count matches orders" $ do
        let (dispatch, _) = mkPendingDispatch
        let count = length testOrderIdentifiers
        case completeDispatch count testOrderIdentifiers fixedTime dispatch of
          Left domainError -> expectationFailure ("Unexpected Left: " ++ show domainError)
          Right (updated, _) -> do
            updated.dispatchStatus `shouldBe` Completed
            updated.orderCount `shouldBe` Just count
            updated.orders `shouldBe` testOrderIdentifiers

      it "MUST-11: rejects when orderCount /= length orders (INV-PP-004)" $ do
        let (dispatch, _) = mkPendingDispatch
        -- count=3 but we only provide 2 orders
        completeDispatch 3 testOrderIdentifiers fixedTime dispatch
          `shouldSatisfy` isLeft

      it "MUST-11: rejects when count=0 but orders non-empty" $ do
        let (dispatch, _) = mkPendingDispatch
        completeDispatch 0 testOrderIdentifiers fixedTime dispatch
          `shouldSatisfy` isLeft

      it "accepts count=0 with empty orders" $ do
        let (dispatch, _) = mkPendingDispatch
        completeDispatch 0 [] fixedTime dispatch
          `shouldSatisfy` isRight

      it "emits ProposalDispatchCompleted event with trace" $ do
        let (dispatch, _) = mkPendingDispatch
        let count = length testOrderIdentifiers
        case completeDispatch count testOrderIdentifiers fixedTime dispatch of
          Left domainError -> expectationFailure ("Unexpected Left: " ++ show domainError)
          Right (_, [ProposalDispatchCompleted{trace = t}]) ->
            t `shouldBe` testTrace
          Right (_, events) ->
            expectationFailure ("Expected 1 event, got " ++ show (length events))

      it "rejects non-Pending status" $ do
        let (dispatch, _) = mkPendingDispatch
        case completeDispatch 0 [] fixedTime dispatch of
          Left domainError -> expectationFailure ("Unexpected Left: " ++ show domainError)
          Right (completed, _) ->
            completeDispatch 0 [] fixedTime completed `shouldSatisfy` isLeft

    -- MUST-12: failDispatch invariant (INV-PP-005)
    describe "failDispatch (MUST-12, INV-PP-005)" $ do
      it "MUST-12: rejects when reasonCode is Nothing (INV-PP-005)" $ do
        let (dispatch, _) = mkPendingDispatch
        failDispatch Nothing fixedTime dispatch
          `shouldSatisfy` isLeft

      it "transitions Pending → Failed when reasonCode is provided" $ do
        let (dispatch, _) = mkPendingDispatch
        case failDispatch (Just DependencyTimeout) fixedTime dispatch of
          Left domainError -> expectationFailure ("Unexpected Left: " ++ show domainError)
          Right (updated, _) -> do
            updated.dispatchStatus `shouldBe` Failed
            updated.reasonCode `shouldBe` Just DependencyTimeout

      it "emits ProposalDispatchFailed event with trace and reasonCode" $ do
        let (dispatch, _) = mkPendingDispatch
        case failDispatch (Just RequestValidationFailed) fixedTime dispatch of
          Left domainError -> expectationFailure ("Unexpected Left: " ++ show domainError)
          Right (_, [ProposalDispatchFailed{reasonCode = code, trace = t}]) -> do
            code `shouldBe` RequestValidationFailed
            t `shouldBe` testTrace
          Right (_, events) ->
            expectationFailure ("Expected 1 event, got " ++ show (length events))

      it "rejects non-Pending status" $ do
        let (dispatch, _) = mkPendingDispatch
        case failDispatch (Just DependencyTimeout) fixedTime dispatch of
          Left domainError -> expectationFailure ("Unexpected Left: " ++ show domainError)
          Right (failed, _) ->
            failDispatch (Just DependencyUnavailable) fixedTime failed `shouldSatisfy` isLeft
