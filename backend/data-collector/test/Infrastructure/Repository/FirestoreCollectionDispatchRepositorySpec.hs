module Infrastructure.Repository.FirestoreCollectionDispatchRepositorySpec (spec) where

import Data.ULID (ULID, ulidFromInteger)
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (MarketCollectionIdentifier (..))
import Domain.MarketCollection.CollectionDispatch (
  CollectionDispatchRepository (..),
  DispatchStatus (..),
  startDispatch,
 )
import Infrastructure.Repository.FirestoreCollectionDispatchRepository (
  FirestoreCollectionDispatchEnv (..),
  isRetryableForPersist,
  runFirestoreCollectionDispatchRepositoryT,
 )
import Persistence.Firestore (FirestoreContext (..), FirestoreError (..))
import System.Environment (lookupEnv)
import Test.Hspec (Spec, describe, it, pendingWith, shouldBe)

spec :: Spec
spec = do
  describe "FirestoreCollectionDispatchRepositoryT" $ do
    describe "isRetryableForPersist" $ do
      it "returns False for FirestoreErrorDecode" $ do
        isRetryableForPersist (FirestoreErrorDecode "bad") `shouldBe` False

      it "returns True for FirestoreErrorTransport" $ do
        isRetryableForPersist (FirestoreErrorTransport "timeout") `shouldBe` True

      it "returns True for FirestoreErrorUnexpected 429" $ do
        isRetryableForPersist (FirestoreErrorUnexpected 429 "rate limited") `shouldBe` True

    -- TC-INFRA-005: emulator round-trip (pendingWith if no emulator)
    describe "TC-INFRA-005: persist -> find round-trip" $ do
      it "persists and finds CollectionDispatch" $ do
        maybeEmulator <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulator of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore emulator tests"
          Just _ -> do
            let context = FirestoreContext{projectId = "test-project", databaseId = "(default)"}
                environment = FirestoreCollectionDispatchEnv{firestoreContext = context}
                collectionIdentifier = MarketCollectionIdentifier{value = testUlid}
                traceValue = Trace{value = testUlid}
                dispatch = startDispatch collectionIdentifier traceValue
            runFirestoreCollectionDispatchRepositoryT environment $
              persist dispatch
            result <-
              runFirestoreCollectionDispatchRepositoryT environment $
                find collectionIdentifier
            case result of
              Nothing -> fail "expected Just CollectionDispatch"
              Just found -> found.dispatchStatus `shouldBe` Pending

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 3 of
  Right ulid -> ulid
  Left _ -> error "test ulid"
