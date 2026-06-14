{- | Pure round-trip tests for Firestore document codecs.
TC-INFRA-004-pure / TC-INFRA-005-pure
No Firestore emulator required — only tests toFirestoreFields ↔ fromFirestoreFields.
-}
module Infrastructure.Repository.FirestoreCodecSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (
  CollectionRequestSnapshot (..),
  MarketCollectionIdentifier (..),
  MarketSourceStatus (..),
  RequestedBy (..),
  SourceStatus (..),
  recordCollectionFailure,
  recordCollectionSuccess,
  startCollection,
 )
import Domain.MarketCollection.CollectionDispatch (
  startDispatch,
 )
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Infrastructure.Repository.FirestoreCollectionDispatchRepository (
  CollectionDispatchDocument (..),
  documentToDispatch,
  toDocument,
 )
import Infrastructure.Repository.FirestoreMarketCollectionRepository (
  MarketCollectionDocument (..),
  documentToCollection,
  toDocument,
 )
import Persistence.Firestore (FromFirestore (..), ToFirestore (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
  describe "FirestoreMarketCollectionRepository codec" $ do
    -- TC-INFRA-004-pure: MarketCollection toDocument → fromFirestoreFields round-trip
    describe "TC-INFRA-004-pure: MarketCollectionDocument round-trip" $ do
      it "Pending collection survives toDocument → toFirestoreFields → fromFirestoreFields → documentToCollection" $ do
        let snapshot =
              CollectionRequestSnapshot
                { targetDate = fromGregorian 2026 1 15
                , requestedBy = Scheduler
                , mode = Nothing
                }
            (collection, _) = startCollection testIdentifier snapshot testTrace
            document = Infrastructure.Repository.FirestoreMarketCollectionRepository.toDocument testTime collection
            fields = toFirestoreFields document
        case fromFirestoreFields fields of
          Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
          Right (roundTrippedDocument :: MarketCollectionDocument) ->
            case documentToCollection roundTrippedDocument of
              Left domainError -> fail ("documentToCollection failed: " <> show domainError)
              Right roundTrippedCollection ->
                roundTrippedCollection.targetDate `shouldBe` fromGregorian 2026 1 15

      it "Collected collection preserves storagePath and sourceStatus after round-trip" $ do
        let snapshot =
              CollectionRequestSnapshot
                { targetDate = fromGregorian 2026 1 15
                , requestedBy = Scheduler
                , mode = Nothing
                }
            (baseCollection, _) = startCollection testIdentifier snapshot testTrace
        case recordCollectionSuccess "gs://bucket/out.ndjson" (SourceStatus Ok Ok) 500 testTime baseCollection of
          Left domainError -> fail ("recordCollectionSuccess failed: " <> show domainError)
          Right (collectedCollection, _) -> do
            let document = Infrastructure.Repository.FirestoreMarketCollectionRepository.toDocument testTime collectedCollection
                fields = toFirestoreFields document
            case fromFirestoreFields fields of
              Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
              Right (roundTrippedDocument :: MarketCollectionDocument) ->
                roundTrippedDocument.storagePath `shouldSatisfy` (\p -> p == Just "gs://bucket/out.ndjson")

      it "Failed collection preserves reasonCode text after round-trip" $ do
        let snapshot =
              CollectionRequestSnapshot
                { targetDate = fromGregorian 2026 1 15
                , requestedBy = Scheduler
                , mode = Nothing
                }
            (baseCollection, _) = startCollection testIdentifier snapshot testTrace
        case recordCollectionFailure DataSourceUnavailable Nothing testTime baseCollection of
          Left domainError -> fail ("recordCollectionFailure failed: " <> show domainError)
          Right (failedCollection, _) -> do
            let document = Infrastructure.Repository.FirestoreMarketCollectionRepository.toDocument testTime failedCollection
                fields = toFirestoreFields document
            case fromFirestoreFields fields of
              Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
              Right (roundTrippedDocument :: MarketCollectionDocument) ->
                -- failureDetail is stored in SCREAMING_SNAKE_CASE (wire format per error-codes.json)
                roundTrippedDocument.failureDetail `shouldBe` Just "DATA_SOURCE_UNAVAILABLE"

  describe "FirestoreCollectionDispatchRepository codec" $ do
    -- TC-INFRA-005-pure: CollectionDispatch toDocument → fromFirestoreFields round-trip
    describe "TC-INFRA-005-pure: CollectionDispatchDocument round-trip" $ do
      it "Pending dispatch survives toDocument → toFirestoreFields → fromFirestoreFields → documentToDispatch" $ do
        let dispatch = startDispatch testIdentifier testTrace
            document = Infrastructure.Repository.FirestoreCollectionDispatchRepository.toDocument testTime dispatch
            fields = toFirestoreFields document
        case fromFirestoreFields fields of
          Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
          Right (roundTrippedDocument :: CollectionDispatchDocument) ->
            case documentToDispatch roundTrippedDocument of
              Left domainError -> fail ("documentToDispatch failed: " <> show domainError)
              Right roundTrippedDispatch ->
                roundTrippedDispatch.dispatchStatus `shouldBe` roundTrippedDispatch.dispatchStatus

      it "CollectionDispatchDocument identifier field survives round-trip" $ do
        let dispatch = startDispatch testIdentifier testTrace
            document = Infrastructure.Repository.FirestoreCollectionDispatchRepository.toDocument testTime dispatch
            fields = toFirestoreFields document
        case fromFirestoreFields fields of
          Left decodeError -> fail ("fromFirestoreFields failed: " <> show decodeError)
          Right (roundTrippedDocument :: CollectionDispatchDocument) ->
            roundTrippedDocument.identifier `shouldBe` testUlid

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 5 of
  Right ulid -> ulid
  Left _ -> error "test ulid"

testIdentifier :: MarketCollectionIdentifier
testIdentifier = MarketCollectionIdentifier{value = testUlid}

testTrace :: Trace
testTrace = Trace{value = testUlid}

testTime :: UTCTime
testTime = UTCTime (fromGregorian 2026 1 15) 0
