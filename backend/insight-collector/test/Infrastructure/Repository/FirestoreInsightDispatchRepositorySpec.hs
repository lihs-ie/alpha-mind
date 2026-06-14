module Infrastructure.Repository.FirestoreInsightDispatchRepositorySpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Data.ULID (ulidFromInteger)
import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (InsightCollectionIdentifier (..))
import Domain.InsightCollection.InsightDispatch (
  DispatchStatus (..),
  InsightDispatch,
  InsightDispatchRepository (..),
  PublishedEventType (..),
  markDispatchFailed,
  markDispatched,
  startDispatch,
 )
import Domain.InsightCollection.ReasonCode (ReasonCode (..))
import Infrastructure.Repository.FirestoreInsightDispatchRepository (
  FirestoreInsightDispatchEnv (..),
  documentToDispatch,
  isRetryableForPersist,
  runFirestoreInsightDispatchRepositoryT,
  toDocument,
 )
import Persistence.Firestore (FirestoreContext (..), FirestoreError (..))
import System.Environment (lookupEnv)
import Test.Hspec (Spec, describe, it, pendingWith, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

sampleIdentifier :: InsightCollectionIdentifier
sampleIdentifier =
  InsightCollectionIdentifier
    { value = case ulidFromInteger 1001 of Right u -> u; Left _ -> error "ulid"
    }

sampleTrace :: Trace
sampleTrace =
  Trace
    { value = case ulidFromInteger 1002 of Right u -> u; Left _ -> error "ulid"
    }

sampleTimestamp :: UTCTime
sampleTimestamp = UTCTime (fromGregorian 2026 6 15) (secondsToDiffTime 0)

isFoundPending :: Maybe InsightDispatch -> Bool
isFoundPending (Just d) = d.dispatchStatus == Pending
isFoundPending Nothing = False

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "FirestoreInsightDispatchRepositoryT" $ do
    describe "isRetryableForPersist" $ do
      it "returns False for FirestoreErrorDecode" $
        isRetryableForPersist (FirestoreErrorDecode "bad") `shouldBe` False

      it "returns True for FirestoreErrorTransport" $
        isRetryableForPersist (FirestoreErrorTransport "timeout") `shouldBe` True

      it "returns True for FirestoreErrorUnexpected 429" $
        isRetryableForPersist (FirestoreErrorUnexpected 429 "rate limited") `shouldBe` True

      it "returns True for FirestoreErrorUnexpected 503" $
        isRetryableForPersist (FirestoreErrorUnexpected 503 "unavailable") `shouldBe` True

      it "returns False for FirestoreErrorUnexpected 400" $
        isRetryableForPersist (FirestoreErrorUnexpected 400 "bad request") `shouldBe` False

      it "returns False for FirestoreErrorPermissionDenied" $
        isRetryableForPersist (FirestoreErrorPermissionDenied "denied") `shouldBe` False

    describe "toDocument / documentToDispatch round-trip" $ do
      it "round-trips a Pending dispatch" $ do
        let dispatch = startDispatch sampleIdentifier sampleTrace
            document = toDocument sampleTimestamp dispatch
        case documentToDispatch document of
          Left errMsg -> fail ("documentToDispatch failed: " <> show errMsg)
          Right decoded -> decoded.dispatchStatus `shouldBe` Pending

      it "round-trips a Published dispatch (InsightCollected)" $ do
        let baseDispatch = startDispatch sampleIdentifier sampleTrace
        case markDispatched InsightCollected sampleTimestamp baseDispatch of
          Left domainError -> fail ("markDispatched failed: " <> show domainError)
          Right dispatch -> do
            let document = toDocument sampleTimestamp dispatch
            case documentToDispatch document of
              Left errMsg -> fail ("documentToDispatch failed: " <> show errMsg)
              Right decoded -> do
                decoded.dispatchStatus `shouldBe` Published
                decoded.publishedEvent `shouldSatisfy` (== Just InsightCollected)

      it "round-trips a Published dispatch (InsightCollectFailed)" $ do
        let baseDispatch = startDispatch sampleIdentifier sampleTrace
        case markDispatched InsightCollectFailed sampleTimestamp baseDispatch of
          Left domainError -> fail ("markDispatched failed: " <> show domainError)
          Right dispatch -> do
            let document = toDocument sampleTimestamp dispatch
            case documentToDispatch document of
              Left errMsg -> fail ("documentToDispatch failed: " <> show errMsg)
              Right decoded ->
                decoded.publishedEvent `shouldSatisfy` (== Just InsightCollectFailed)

      it "round-trips a Failed dispatch" $ do
        let baseDispatch = startDispatch sampleIdentifier sampleTrace
        case markDispatchFailed DependencyTimeout sampleTimestamp baseDispatch of
          Left domainError -> fail ("markDispatchFailed failed: " <> show domainError)
          Right dispatch -> do
            let document = toDocument sampleTimestamp dispatch
            case documentToDispatch document of
              Left errMsg -> fail ("documentToDispatch failed: " <> show errMsg)
              Right decoded -> do
                decoded.dispatchStatus `shouldBe` Failed
                decoded.reasonCode `shouldSatisfy` (== Just DependencyTimeout)

    -- Emulator integration tests
    describe "TC-INFRA-012: persistDispatch -> findDispatch round-trip" $ do
      it "persists and finds InsightDispatch via Firestore emulator" $ do
        maybeEmulator <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulator of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore emulator tests"
          Just _ -> do
            let context = FirestoreContext{projectId = "test-project", databaseId = "(default)"}
                environment = FirestoreInsightDispatchEnv{firestoreContext = context}
                dispatch = startDispatch sampleIdentifier sampleTrace
            runFirestoreInsightDispatchRepositoryT environment $
              persistDispatch dispatch
            result <-
              runFirestoreInsightDispatchRepositoryT environment $
                findDispatch sampleIdentifier
            result `shouldSatisfy` isFoundPending
