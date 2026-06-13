{-# OPTIONS_GHC -fno-hpc #-}

{- | Unit tests for FirestoreAuditIngestionRepository codec logic.

Integration tests that require a live Firestore emulator (TST-AU-002
idempotency round-trip) are in the integration test module which is
skipped when FIRESTORE_EMULATOR_HOST is not set.

Must-2: These tests call the production 'auditIngestionDocumentKey' function
directly to avoid tautological self-assertions.
-}
module Infrastructure.Repository.FirestoreAuditIngestionRepositorySpec (spec) where

import Data.Text qualified as Text
import Data.ULID (ULID)
import Infrastructure.Repository.FirestoreAuditIngestionRepository (auditIngestionDocumentKey)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------------

sampleULID :: ULID
sampleULID = case readMaybe "01ARZ3NDEKTSV4RRFFQ69G5FAV" of
  Just ulid -> ulid
  Nothing -> error "invalid ULID literal in test fixture"

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "AuditIngestionRepository DocumentId (Must-2)" $ do
    it "idempotency_keys document key is 'audit-log:{identifier}'" $ do
      let key = auditIngestionDocumentKey sampleULID
          expected = "audit-log:" <> Text.pack (show sampleULID)
      -- Must-2: Production auditIngestionDocumentKey must produce "audit-log:{ulid}"
      key `shouldBe` expected

    it "document key includes service prefix" $ do
      let key = auditIngestionDocumentKey sampleULID
      -- Prefix check: must start with "audit-log:"
      Text.isPrefixOf "audit-log:" key `shouldBe` True

    it "document key suffix is the ULID string and is round-trippable" $ do
      let key = auditIngestionDocumentKey sampleULID
          suffix = Text.drop (Text.length "audit-log:") key
      -- Suffix should be parseable back as the original ULID
      (readMaybe (Text.unpack suffix) :: Maybe ULID) `shouldBe` Just sampleULID
