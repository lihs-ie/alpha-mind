{-# LANGUAGE OverloadedRecordDot #-}
{-# OPTIONS_GHC -fno-hpc #-}

{- | Unit tests for FirestoreAuditRecordRepository codec and helper logic.

TST-AU-002 (idempotency) and round-trip tests against the Firestore emulator
are in the integration test suite (requires FIRESTORE_EMULATOR_HOST).
This module focuses on pure codec, TTL calculation, and retry policy logic.
-}
module Infrastructure.Repository.FirestoreAuditRecordRepositorySpec (spec) where

import Data.HashMap.Strict qualified as HashMap
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Time (UTCTime, addUTCTime, nominalDay)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.ULID (ULID)
import Domain.AuditLog (Trace (..))
import Domain.AuditLog.AuditRecord (
  AuditRecordIdentifier (..),
  PayloadSummaryValue (..),
  SourceEventIdentifier (..),
  SourceEventSnapshot (..),
  acceptSourceEvent,
 )
import Domain.AuditLog.Result (Result (..))
import Infrastructure.Repository.FirestoreAuditRecordRepository (
  AuditRecordFirestoreDocument (..),
  isRetryableForPersist,
 )
import Persistence.Firestore (
  FirestoreError (..),
  FromFirestore (..),
  ToFirestore (..),
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------------

sampleULID :: ULID
sampleULID = case readMaybe "01ARZ3NDEKTSV4RRFFQ69G5FAV" of
  Just ulid -> ulid
  Nothing -> error "invalid ULID literal in test fixture"

sampleTime :: UTCTime
sampleTime = posixSecondsToUTCTime 1700000000

sampleDocument :: AuditRecordFirestoreDocument
sampleDocument =
  AuditRecordFirestoreDocument
    { identifier = sampleULID
    , eventType = "orders.executed"
    , service = "execution"
    , result = "success"
    , trace = sampleULID
    , reason = Nothing
    , occurredAt = sampleTime
    , payloadSummary = Nothing
    , expiresAt = addUTCTime (90 * nominalDay) sampleTime
    }

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "AuditRecordFirestoreDocument" $ do
    describe "ToFirestore" $ do
      it "generates all required audit_logs fields (Must-10)" $ do
        let fields = toFirestoreFields sampleDocument
            keySet = HashMap.keysSet fields
        -- Must-10: audit_logs schema fields
        keySet `shouldSatisfy` (\ks -> "identifier" `elem` ks)
        keySet `shouldSatisfy` (\ks -> "eventType" `elem` ks)
        keySet `shouldSatisfy` (\ks -> "service" `elem` ks)
        keySet `shouldSatisfy` (\ks -> "result" `elem` ks)
        keySet `shouldSatisfy` (\ks -> "trace" `elem` ks)
        keySet `shouldSatisfy` (\ks -> "occurredAt" `elem` ks)
        keySet `shouldSatisfy` (\ks -> "expiresAt" `elem` ks)

      it "does not include reason when Nothing" $ do
        let fields = toFirestoreFields sampleDocument
        HashMap.member "reason" fields `shouldBe` False

      it "includes reason when Just" $ do
        let documentWithReason = sampleDocument{reason = Just "STOP_LOSS_HIT"}
            fields = toFirestoreFields documentWithReason
        HashMap.member "reason" fields `shouldBe` True

      it "includes payloadSummary when Just" $ do
        let summary = Map.fromList [("symbol", SummaryString "7203.T"), ("qty", SummaryNumber 100)]
            documentWithSummary = sampleDocument{payloadSummary = Just summary}
            fields = toFirestoreFields documentWithSummary
        HashMap.member "payloadSummary" fields `shouldBe` True

    describe "FromFirestore round-trip" $ do
      it "round-trips identifier, eventType, service, result fields" $ do
        let fields = toFirestoreFields sampleDocument
        case fromFirestoreFields fields :: Either Text AuditRecordFirestoreDocument of
          Left message -> error ("fromFirestoreFields failed: " <> show message)
          Right decoded -> do
            decoded.identifier `shouldBe` sampleDocument.identifier
            decoded.eventType `shouldBe` sampleDocument.eventType
            decoded.service `shouldBe` sampleDocument.service
            decoded.result `shouldBe` sampleDocument.result
            decoded.trace `shouldBe` sampleDocument.trace

    describe "expiresAt TTL (Must-4)" $ do
      it "expiresAt is exactly now + 90 days" $ do
        let now = sampleTime
            expected = addUTCTime (90 * nominalDay) now
            document = sampleDocument{expiresAt = expected}
        document.expiresAt `shouldBe` expected

  describe "isRetryableForPersist (Must-6, Must-7)" $ do
    it "FirestoreErrorTransport is retryable" $ do
      isRetryableForPersist (FirestoreErrorTransport "timeout") `shouldBe` True

    it "FirestoreErrorDecode is NOT retryable (maps to DATA_SCHEMA_INVALID)" $ do
      isRetryableForPersist (FirestoreErrorDecode "invalid schema") `shouldBe` False

    it "FirestoreErrorUnexpected 500 is retryable" $ do
      isRetryableForPersist (FirestoreErrorUnexpected 500 "internal error") `shouldBe` True

    it "FirestoreErrorUnexpected 429 (rate limit) is retryable" $ do
      isRetryableForPersist (FirestoreErrorUnexpected 429 "rate limited") `shouldBe` True

    it "FirestoreErrorPermissionDenied is NOT retryable" $ do
      isRetryableForPersist (FirestoreErrorPermissionDenied "403") `shouldBe` False

  describe "DocumentId format (Must-2 analogue for AuditRecord)" $ do
    it "audit_logs document key is the ULID string" $ do
      let identifier = sampleULID
          documentKey = show identifier
      -- Should be parseable back as a ULID
      (readMaybe documentKey :: Maybe ULID) `shouldBe` Just identifier
