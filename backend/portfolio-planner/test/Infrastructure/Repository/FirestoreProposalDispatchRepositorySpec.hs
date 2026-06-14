{-# LANGUAGE LambdaCase #-}

{- | Pure codec round-trip tests for FirestoreProposalDispatchRepository.
No Firestore emulator required.
Must-07: codec round-trip / unknown status → Left.
-}
module Infrastructure.Repository.FirestoreProposalDispatchRepositorySpec (spec) where

import Data.Time (UTCTime (..), fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.ProposalDispatch (
  DispatchStatus (..),
  ProposalDispatch,
  ProposalDispatchIdentifier (..),
  startDispatch,
 )
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
 )
import Infrastructure.Repository.FirestoreProposalDispatchRepository (
  ProposalDispatchDocument (..),
  documentToDispatch,
  isRetryableForPersist,
  toDocument,
 )
import Persistence.Firestore (FirestoreError (..), FromFirestore (..), ToFirestore (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
  describe "FirestoreProposalDispatchRepository codec" $ do
    describe "isRetryableForPersist" $ do
      it "returns False for FirestoreErrorDecode" $ do
        isRetryableForPersist (FirestoreErrorDecode "bad") `shouldBe` False

      it "returns True for FirestoreErrorTransport" $ do
        isRetryableForPersist (FirestoreErrorTransport "timeout") `shouldBe` True

      it "returns True for FirestoreErrorUnexpected 429" $ do
        isRetryableForPersist (FirestoreErrorUnexpected 429 "rate limited") `shouldBe` True

    describe "ProposalDispatchDocument round-trip" $ do
      it "Pending dispatch survives toDocument → toFirestoreFields → fromFirestoreFields → documentToDispatch" $ do
        let dispatch = testDispatch
            document = toDocument testTime dispatch
            fields = toFirestoreFields document
        case fromFirestoreFields fields of
          Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
          Right (roundTrippedDocument :: ProposalDispatchDocument) ->
            case documentToDispatch roundTrippedDocument of
              Left domainError -> fail ("documentToDispatch failed: " <> show domainError)
              Right roundTrippedDispatch ->
                roundTrippedDispatch.dispatchStatus `shouldBe` Pending

      it "identifier field survives round-trip" $ do
        let document = toDocument testTime testDispatch
            fields = toFirestoreFields document
        case fromFirestoreFields fields of
          Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
          Right (roundTrippedDocument :: ProposalDispatchDocument) ->
            roundTrippedDocument.identifier `shouldBe` testUlid

      it "dispatchStatus=pending survives round-trip" $ do
        let document = toDocument testTime testDispatch
            fields = toFirestoreFields document
        case fromFirestoreFields fields of
          Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
          Right (roundTrippedDocument :: ProposalDispatchDocument) ->
            roundTrippedDocument.dispatchStatus `shouldBe` "pending"

      it "unknown dispatchStatus string → Left from documentToDispatch" $ do
        let document =
              ProposalDispatchDocument
                { identifier = testUlid
                , dispatchStatus = "UNKNOWN_STATUS"
                , orderCount = Nothing
                , orders = ""
                , reasonCode = Nothing
                , trace = testUlid
                , processedAt = Nothing
                }
        documentToDispatch document `shouldSatisfy` \case
          Left _ -> True
          Right _ -> False

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 11 of
  Right ulid -> ulid
  Left _ -> error "test ulid"

testTime :: UTCTime
testTime = UTCTime (fromGregorian 2026 1 15) 0

testSignalSnapshot :: SignalSnapshot
testSignalSnapshot =
  SignalSnapshot
    { signalVersion = "v1.0"
    , modelVersion = "m1.0"
    , featureVersion = "f1.0"
    , storagePath = "gs://bucket/signals/v1.parquet"
    , degradationFlag = Normal
    , requiresComplianceReview = False
    }

testDispatch :: ProposalDispatch
testDispatch =
  let (dispatch, _) =
        startDispatch
          ProposalDispatchIdentifier{value = testUlid}
          testSignalSnapshot
          Trace{value = testUlid}
   in dispatch
