module Infrastructure.Repository.FirestoreInsightRecordRepositorySpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.ULID (ulidFromInteger)
import Domain.InsightCollection.Aggregate (
  InsightRecord (..),
  InsightRecordIdentifier (..),
  InsightRecordRepository (..),
  SignalClass (..),
  SourceType (..),
 )
import Infrastructure.Repository.FirestoreInsightRecordRepository (
  FirestoreInsightRecordEnv (..),
  documentToRecord,
  insightRecordDocumentExpiresAt,
  isRetryableForPersist,
  runFirestoreInsightRecordRepositoryT,
  toDocument,
 )
import Persistence.Firestore (FirestoreContext (..), FirestoreError (..))
import System.Environment (lookupEnv)
import Test.Hspec (Spec, describe, it, pendingWith, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

sampleRecord :: InsightRecord
sampleRecord =
  InsightRecord
    { identifier = InsightRecordIdentifier{value = case ulidFromInteger 42 of Right u -> u; Left _ -> error "ulid"}
    , sourceType = X
    , sourceUrl = "https://x.com/user/status/12345"
    , evidenceSnippet = "Market analysis shows bullish trend for Japanese equities."
    , collectedAt = UTCTime (fromGregorian 2026 6 14) (secondsToDiffTime 0)
    , summary = "Bullish signal for Japan equities Q2 2026"
    , signalClass = StructuralAnomaly
    , soWhatScore = 0.75
    , skillVersion = "1.0.0"
    }

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "FirestoreInsightRecordRepositoryT" $ do
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

      it "returns False for FirestoreErrorPermissionDenied" $ do
        isRetryableForPersist (FirestoreErrorPermissionDenied "denied") `shouldBe` False

    -- Pure codec round-trip tests
    describe "toDocument / documentToRecord round-trip" $ do
      it "round-trips an InsightRecord with SourceType X" $ do
        let document = toDocument sampleRecord
        case documentToRecord document of
          Left errMsg -> fail ("documentToRecord failed: " <> show errMsg)
          Right record -> do
            record.sourceType `shouldBe` X
            record.sourceUrl `shouldBe` sampleRecord.sourceUrl
            record.evidenceSnippet `shouldBe` sampleRecord.evidenceSnippet
            record.signalClass `shouldBe` StructuralAnomaly
            record.skillVersion `shouldBe` sampleRecord.skillVersion

      it "round-trips soWhatScore within floating-point precision" $ do
        let document = toDocument sampleRecord
        case documentToRecord document of
          Left errMsg -> fail ("documentToRecord failed: " <> show errMsg)
          Right record ->
            abs (record.soWhatScore - sampleRecord.soWhatScore) `shouldSatisfy` (< 0.001)

      it "round-trips signalClass EventNoise" $ do
        let eventNoiseRecord = sampleRecord{signalClass = EventNoise, soWhatScore = 0.50}
        let document = toDocument eventNoiseRecord
        case documentToRecord document of
          Left errMsg -> fail ("documentToRecord failed: " <> show errMsg)
          Right record -> record.signalClass `shouldBe` EventNoise

      it "round-trips all SourceType values" $ do
        let sourceTypes = [X, YouTube, Paper, GitHub]
        mapM_
          ( \sourceTypeValue -> do
              let record = sampleRecord{sourceType = sourceTypeValue}
              let document = toDocument record
              case documentToRecord document of
                Left errMsg -> fail ("documentToRecord failed for " <> show sourceTypeValue <> ": " <> show errMsg)
                Right decoded -> decoded.sourceType `shouldBe` sourceTypeValue
          )
          sourceTypes

      it "sets expiresAt to collectedAt + 365 days" $ do
        let document = toDocument sampleRecord
            expectedYear = 2027 :: Int
            -- expiresAt should be 365 days after collectedAt (2026-06-14 → 2027-06-14)
            expiresAtValue = insightRecordDocumentExpiresAt document
            expiresYear = read (take 4 (formatTime defaultTimeLocale "%Y" expiresAtValue)) :: Int
        expiresYear `shouldBe` expectedYear

    -- Emulator integration tests
    describe "TC-INFRA-001: persistRecord -> findByTargetDate round-trip" $ do
      it "persists and finds InsightRecord via Firestore emulator" $ do
        maybeEmulator <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulator of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore emulator tests"
          Just _ -> do
            let context = FirestoreContext{projectId = "test-project", databaseId = "(default)"}
                environment = FirestoreInsightRecordEnv{firestoreContext = context}
            runFirestoreInsightRecordRepositoryT environment $
              persistRecord sampleRecord
            results <-
              runFirestoreInsightRecordRepositoryT environment $
                findByTargetDate (fromGregorian 2026 6 14)
            results `shouldSatisfy` (not . null)
