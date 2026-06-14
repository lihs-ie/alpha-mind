{- | Pure codec round-trip tests for FirestoreOrderProposalRepository.
No Firestore emulator required.
Must-07: codec round-trip / unknown status → Left.
-}
module Infrastructure.Repository.FirestoreOrderProposalRepositorySpec (spec) where

import Data.Ratio ((%))
import Data.Time (UTCTime (..), fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Aggregate (
  OrderProposal,
  OrderProposalIdentifier (..),
  Side (..),
  createProposal,
 )
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
  StrategySnapshot (..),
 )
import Infrastructure.Repository.FirestoreOrderProposalRepository (
  OrderProposalDocument (..),
  documentToProposal,
  isRetryableForPersist,
  toDocument,
 )
import Persistence.Firestore (FirestoreError (..), FromFirestore (..), ToFirestore (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
  describe "FirestoreOrderProposalRepository codec" $ do
    describe "isRetryableForPersist" $ do
      it "returns False for FirestoreErrorDecode" $ do
        isRetryableForPersist (FirestoreErrorDecode "bad") `shouldBe` False

      it "returns True for FirestoreErrorTransport" $ do
        isRetryableForPersist (FirestoreErrorTransport "timeout") `shouldBe` True

      it "returns True for FirestoreErrorUnexpected 429" $ do
        isRetryableForPersist (FirestoreErrorUnexpected 429 "rate limited") `shouldBe` True

      it "returns True for FirestoreErrorUnexpected 500" $ do
        isRetryableForPersist (FirestoreErrorUnexpected 500 "server error") `shouldBe` True

      it "returns False for FirestoreErrorUnexpected 400" $ do
        isRetryableForPersist (FirestoreErrorUnexpected 400 "bad request") `shouldBe` False

    describe "OrderProposalDocument round-trip" $ do
      it "Proposed proposal survives toDocument → toFirestoreFields → fromFirestoreFields → documentToProposal" $ do
        let proposal = testProposal
            document = toDocument testTime proposal
            fields = toFirestoreFields document
        case fromFirestoreFields fields of
          Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
          Right (roundTrippedDocument :: OrderProposalDocument) ->
            case documentToProposal roundTrippedDocument of
              Left domainError -> fail ("documentToProposal failed: " <> show domainError)
              Right roundTrippedProposal ->
                roundTrippedProposal.symbol `shouldBe` "7203.T"

      it "identifier field survives round-trip" $ do
        let document = toDocument testTime testProposal
            fields = toFirestoreFields document
        case fromFirestoreFields fields of
          Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
          Right (roundTrippedDocument :: OrderProposalDocument) ->
            roundTrippedDocument.identifier `shouldBe` testUlid

      it "side=Buy survives round-trip" $ do
        let document = toDocument testTime testProposal
            fields = toFirestoreFields document
        case fromFirestoreFields fields of
          Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
          Right (roundTrippedDocument :: OrderProposalDocument) ->
            roundTrippedDocument.side `shouldBe` "BUY"

      it "status=PROPOSED survives round-trip" $ do
        let document = toDocument testTime testProposal
            fields = toFirestoreFields document
        case fromFirestoreFields fields of
          Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
          Right (roundTrippedDocument :: OrderProposalDocument) ->
            roundTrippedDocument.status `shouldBe` "PROPOSED"

      it "unknown status string → Left from documentToProposal" $ do
        let document =
              OrderProposalDocument
                { identifier = testUlid
                , symbol = "7203.T"
                , side = "BUY"
                , qty = "100 % 1"
                , status = "UNKNOWN_STATUS"
                , trace = testUlid
                , createdAt = testTime
                }
        documentToProposal document `shouldSatisfy` \result -> case result of
          Left _ -> True
          Right _ -> False

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 10 of
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

testStrategySnapshot :: StrategySnapshot
testStrategySnapshot =
  StrategySnapshot
    { maxOrderCount = 10
    , maxSingleOrderQty = 100
    , rebalanceThreshold = 5 % 100
    }

testProposal :: OrderProposal
testProposal =
  case createProposal
    (OrderProposalIdentifier{value = testUlid})
    "7203.T"
    Buy
    100
    testSignalSnapshot
    Nothing
    testStrategySnapshot
    (Trace{value = testUlid})
    testTime of
    Right (proposal, _) -> proposal
    Left domainError -> error ("test proposal: " <> show domainError)
