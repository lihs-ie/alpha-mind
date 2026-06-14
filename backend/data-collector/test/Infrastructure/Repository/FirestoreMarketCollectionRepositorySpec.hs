module Infrastructure.Repository.FirestoreMarketCollectionRepositorySpec (spec) where

import Data.Time (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (
  CollectionRequestSnapshot (..),
  CollectionStatus (..),
  MarketCollectionIdentifier (..),
  MarketCollectionRepository (..),
  RequestedBy (..),
  startCollection,
 )
import Infrastructure.Repository.FirestoreMarketCollectionRepository (
  FirestoreMarketCollectionEnv (..),
  isRetryableForPersist,
  runFirestoreMarketCollectionRepositoryT,
 )
import Persistence.Firestore (FirestoreContext (..), FirestoreError (..))
import System.Environment (lookupEnv)
import Test.Hspec (Spec, describe, it, pendingWith, shouldBe)

spec :: Spec
spec = do
  describe "FirestoreMarketCollectionRepositoryT" $ do
    -- Pure retry predicate tests
    describe "isRetryableForPersist" $ do
      it "returns False for FirestoreErrorDecode" $ do
        isRetryableForPersist (FirestoreErrorDecode "bad") `shouldBe` False

      it "returns True for FirestoreErrorTransport" $ do
        isRetryableForPersist (FirestoreErrorTransport "timeout") `shouldBe` True

      it "returns True for FirestoreErrorUnexpected 429" $ do
        isRetryableForPersist (FirestoreErrorUnexpected 429 "rate limited") `shouldBe` True

      it "returns True for FirestoreErrorUnexpected 503" $ do
        isRetryableForPersist (FirestoreErrorUnexpected 503 "unavailable") `shouldBe` True

      it "returns False for FirestoreErrorUnexpected 400" $ do
        isRetryableForPersist (FirestoreErrorUnexpected 400 "bad request") `shouldBe` False

    -- TC-INFRA-004: emulator round-trip (pendingWith if no emulator)
    describe "TC-INFRA-004: persist -> find round-trip" $ do
      it "persists and finds MarketCollection" $ do
        maybeEmulator <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulator of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore emulator tests"
          Just _ -> do
            let context = FirestoreContext{projectId = "test-project", databaseId = "(default)"}
                environment = FirestoreMarketCollectionEnv{firestoreContext = context}
                collectionIdentifier = MarketCollectionIdentifier{value = testUlid}
                traceValue = Trace{value = testUlid}
                snapshot =
                  CollectionRequestSnapshot
                    { targetDate = fromGregorian 2026 1 15
                    , requestedBy = Scheduler
                    , mode = Nothing
                    }
                (collection, _) = startCollection collectionIdentifier snapshot traceValue
            runFirestoreMarketCollectionRepositoryT environment $
              persist collection
            result <-
              runFirestoreMarketCollectionRepositoryT environment $
                find collectionIdentifier
            case result of
              Nothing -> fail "expected Just MarketCollection"
              Just found -> found.status `shouldBe` Pending

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 2 of
  Right ulid -> ulid
  Left _ -> error "test ulid"
