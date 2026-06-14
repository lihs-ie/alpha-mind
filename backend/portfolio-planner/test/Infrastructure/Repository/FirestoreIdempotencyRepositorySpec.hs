{- | Pure codec tests for FirestoreIdempotencyRepository.
No Firestore emulator required.
Must-07: documentId = "portfolio-planner:{ulid}", codec round-trip.
-}
module Infrastructure.Repository.FirestoreIdempotencyRepositorySpec (spec) where

import Data.Text qualified as Text
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
import Infrastructure.Repository.FirestoreIdempotencyRepository (
  IdempotencyDocument (..),
  documentToDispatch,
  idempotencyDocumentId,
  isRetryableForPersist,
  toDocument,
 )
import Persistence.Firestore (DocumentId (..), FirestoreError (..), FromFirestore (..), ToFirestore (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
  describe "FirestoreIdempotencyRepository codec" $ do
    describe "isRetryableForPersist" $ do
      it "returns False for FirestoreErrorDecode" $ do
        isRetryableForPersist (FirestoreErrorDecode "bad") `shouldBe` False

      it "returns True for FirestoreErrorTransport" $ do
        isRetryableForPersist (FirestoreErrorTransport "timeout") `shouldBe` True

    describe "idempotencyDocumentId" $ do
      it "documentId format is portfolio-planner:{ulid}" $ do
        let dispatchIdentifier = ProposalDispatchIdentifier{value = testUlid}
            DocumentId docId = idempotencyDocumentId dispatchIdentifier
        docId `shouldSatisfy` Text.isPrefixOf "portfolio-planner:"

      it "documentId contains ULID string after prefix" $ do
        let dispatchIdentifier = ProposalDispatchIdentifier{value = testUlid}
            DocumentId docId = idempotencyDocumentId dispatchIdentifier
            expectedUlidText = Text.pack (show testUlid)
        docId `shouldBe` ("portfolio-planner:" <> expectedUlidText)

    describe "IdempotencyDocument round-trip" $ do
      it "dispatch survives toDocument → toFirestoreFields → fromFirestoreFields → documentToDispatch" $ do
        let dispatch = testDispatch
            document = toDocument testTime dispatch
            fields = toFirestoreFields document
        case fromFirestoreFields fields of
          Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
          Right (roundTrippedDocument :: IdempotencyDocument) ->
            case documentToDispatch roundTrippedDocument of
              Left domainError -> fail ("documentToDispatch failed: " <> show domainError)
              Right roundTrippedDispatch ->
                roundTrippedDispatch.dispatchStatus `shouldBe` Pending

      it "service field is always portfolio-planner" $ do
        let document = toDocument testTime testDispatch
            fields = toFirestoreFields document
        case fromFirestoreFields fields of
          Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
          Right (roundTrippedDocument :: IdempotencyDocument) ->
            roundTrippedDocument.service `shouldBe` "portfolio-planner"

      it "identifier field survives round-trip" $ do
        let document = toDocument testTime testDispatch
            fields = toFirestoreFields document
        case fromFirestoreFields fields of
          Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
          Right (roundTrippedDocument :: IdempotencyDocument) ->
            roundTrippedDocument.identifier `shouldBe` testUlid

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 12 of
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
