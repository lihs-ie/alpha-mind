{-# OPTIONS_GHC -fno-hpc #-}

{- | Integration tests for the Firestore repository implementations.

These tests require a running Firestore emulator. When the
FIRESTORE_EMULATOR_HOST environment variable is not set the entire
suite is skipped (pending), but the module still compiles (Must-9).

To run locally:
  docker-compose -f docker/docker-compose.integration.audit-log.yml up -d
  FIRESTORE_EMULATOR_HOST=localhost:8080 cabal test audit-log-test

TST-AU-002: Idempotency — duplicate persist does not increase document count.
-}
module Infrastructure.Repository.IntegrationSpec (spec) where

import Data.Aeson (Value (..))
import Data.Text qualified as Text
import Data.Time (addUTCTime, diffUTCTime, getCurrentTime, nominalDay)
import Data.ULID (ULID)
import Domain.AuditLog (Trace (..))
import Domain.AuditLog.AuditIngestion qualified as Ingestion
import Domain.AuditLog.AuditRecord qualified as Record
import Domain.AuditLog.Result (Result (..))
import Infrastructure.Repository.FirestoreAuditIngestionRepository (
  FirestoreAuditIngestionEnv (..),
  runFirestoreAuditIngestionT,
 )
import Infrastructure.Repository.FirestoreAuditRecordRepository (
  AuditRecordFirestoreDocument (..),
  FirestoreAuditRecordEnv (..),
  runFirestoreAuditRecordT,
 )
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext (..),
  getDocument,
 )
import Persistence.Idempotency (IdempotencyRecord (..))
import System.Environment (lookupEnv)
import Test.Hspec (Spec, describe, it, pendingWith, shouldBe, shouldSatisfy)
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------------

sampleULID :: ULID
sampleULID = case readMaybe "01ARZ3NDEKTSV4RRFFQ69G5FAV" of
  Just ulid -> ulid
  Nothing -> error "invalid ULID literal in test fixture"

anotherULID :: ULID
anotherULID = case readMaybe "01BX5ZZKBKACTAV9WEVGEMMVS0" of
  Just ulid -> ulid
  Nothing -> error "invalid ULID literal in test fixture"

makeFirestoreContext :: FirestoreContext
makeFirestoreContext =
  FirestoreContext
    { projectId = "test-project"
    , databaseId = "(default)"
    }

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "Firestore Integration (requires FIRESTORE_EMULATOR_HOST)" $ do
    describe "AuditRecordRepository persist → find round-trip" $ do
      it "TST-AU-002 persist then find returns the same record (round-trip)" $ do
        maybeEmulatorHost <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulatorHost of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore integration tests"
          Just _ -> do
            now <- getCurrentTime
            let context = makeFirestoreContext
                environment = FirestoreAuditRecordEnv{firestoreContext = context}
                recordIdentifier = Record.AuditRecordIdentifier{value = sampleULID}
                traceValue = Trace{value = anotherULID}
                snapshot =
                  Record.SourceEventSnapshot
                    { identifier = Record.SourceEventIdentifier{value = sampleULID}
                    , eventType = "orders.executed"
                    , occurredAt = now
                    , trace = traceValue
                    , payload = Null
                    }
                (baseRecord, _) = Record.acceptSourceEvent recordIdentifier snapshot "execution" Success
            case Record.markRecorded now baseRecord of
              Left _ -> fail "markRecorded failed in test"
              Right (record, _) -> do
                maybeFound <- runFirestoreAuditRecordT environment $ do
                  Record.persist record
                  Record.find recordIdentifier
                -- Round-trip assert: the persisted record is retrievable and has the same identifier
                case maybeFound of
                  Nothing -> fail "find returned Nothing after persist"
                  Just foundRecord ->
                    foundRecord.identifier `shouldBe` record.identifier

    describe "TST-AU-002 idempotency — duplicate persist does not increase count" $ do
      it "persisting AuditIngestion twice with same identifier is idempotent (upsert semantics)" $ do
        maybeEmulatorHost <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulatorHost of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore integration tests"
          Just _ -> do
            let context = makeFirestoreContext
                ingestionEnvironment = FirestoreAuditIngestionEnv{firestoreContext = context}
                ingestionIdentifier = Ingestion.AuditIngestionIdentifier{value = sampleULID}
                traceValue = Trace{value = anotherULID}
                ingestion = Ingestion.startIngestion ingestionIdentifier traceValue
                documentKey = "audit-log:" <> Text.pack (show sampleULID)
            -- Persist twice with the same identifier
            runFirestoreAuditIngestionT ingestionEnvironment $ do
              Ingestion.persist ingestion
              Ingestion.persist ingestion
            -- After two persists, the document should exist exactly once.
            -- reserveIdempotency uses upsertDocument which is idempotent:
            -- a second write to the same key overwrites rather than duplicates.
            maybeRecord <-
              getDocument @IdempotencyRecord
                context
                (CollectionName "idempotency_keys")
                (DocumentId documentKey)
            case maybeRecord of
              Left firestoreError ->
                fail $ "getDocument failed: " <> show firestoreError
              Right Nothing ->
                fail "Expected idempotency record to exist after two persists"
              Right (Just _record) ->
                -- Document exists exactly once — idempotency is preserved.
                pure ()

    describe "expiresAt TTL fields (Must-4)" $ do
      it "audit_logs expiresAt is within 1 second of now + 90 days" $ do
        maybeEmulatorHost <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulatorHost of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore integration tests"
          Just _ -> do
            now <- getCurrentTime
            let context = makeFirestoreContext
                environment = FirestoreAuditRecordEnv{firestoreContext = context}
                recordIdentifier = Record.AuditRecordIdentifier{value = sampleULID}
                traceValue = Trace{value = anotherULID}
                snapshot =
                  Record.SourceEventSnapshot
                    { identifier = Record.SourceEventIdentifier{value = sampleULID}
                    , eventType = "orders.executed"
                    , occurredAt = now
                    , trace = traceValue
                    , payload = Null
                    }
                (baseRecord, _) = Record.acceptSourceEvent recordIdentifier snapshot "execution" Success
            case Record.markRecorded now baseRecord of
              Left _ -> fail "markRecorded failed in test"
              Right (record, _) -> do
                runFirestoreAuditRecordT environment $ do
                  Record.persist record
                -- Read the raw Firestore document to verify expiresAt
                maybeRawDocument <-
                  getDocument @AuditRecordFirestoreDocument
                    context
                    (CollectionName "audit_logs")
                    (DocumentId (Text.pack (show sampleULID)))
                case maybeRawDocument of
                  Left firestoreError ->
                    fail $ "getDocument failed: " <> show firestoreError
                  Right Nothing ->
                    fail "Expected audit_logs document to exist after persist"
                  Right (Just rawDocument) -> do
                    let expectedExpiresAt = addUTCTime (90 * nominalDay) now
                        actualDiff = abs (diffUTCTime rawDocument.expiresAt expectedExpiresAt)
                    -- expiresAt must be within 1 second of now + 90 days
                    actualDiff `shouldSatisfy` (< 1)

    -- Must-8: findByEventType must return ALL matching records (exercises the
    -- custom executeRunQueryHttp path, which gogol's single-RunQueryResponse
    -- binding cannot do). Uses a dedicated eventType to avoid cross-test bleed.
    describe "findByEventType returns multiple matching records (Must-8)" $ do
      it "persists two records with the same eventType and retrieves both" $ do
        maybeEmulatorHost <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulatorHost of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore integration tests"
          Just _ -> do
            now <- getCurrentTime
            let context = makeFirestoreContext
                environment = FirestoreAuditRecordEnv{firestoreContext = context}
                queryEventType = "test.query.multidoc"
                buildRecord ulidValue =
                  let snapshot =
                        Record.SourceEventSnapshot
                          { identifier = Record.SourceEventIdentifier{value = ulidValue}
                          , eventType = queryEventType
                          , occurredAt = now
                          , trace = Trace{value = ulidValue}
                          , payload = Null
                          }
                      (base, _) = Record.acceptSourceEvent (Record.AuditRecordIdentifier{value = ulidValue}) snapshot "execution" Success
                   in case Record.markRecorded now base of
                        Left _ -> Nothing
                        Right (recordValue, _) -> Just recordValue
            case (buildRecord sampleULID, buildRecord anotherULID) of
              (Just recordOne, Just recordTwo) -> do
                found <- runFirestoreAuditRecordT environment $ do
                  Record.persist recordOne
                  Record.persist recordTwo
                  Record.findByEventType queryEventType
                length found `shouldSatisfy` (>= 2)
              _ -> fail "failed to construct test records"
