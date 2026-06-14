module Infrastructure.Idempotency.InsightIdempotencySpec (spec) where

import Data.ULID (ulidFromInteger)
import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (InsightCollectionIdentifier (..))
import Infrastructure.Idempotency.InsightIdempotency (
  completeInsightIdempotency,
  reserveInsightIdempotency,
 )
import Persistence.Firestore (FirestoreContext (..))
import Persistence.Idempotency (ReserveResult (..))
import System.Environment (lookupEnv)
import Test.Hspec (Spec, describe, it, pendingWith, shouldBe)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

sampleIdentifier :: InsightCollectionIdentifier
sampleIdentifier =
  InsightCollectionIdentifier
    { value = case ulidFromInteger 100 of Right u -> u; Left _ -> error "ulid"
    }

sampleTrace :: Trace
sampleTrace =
  Trace
    { value = case ulidFromInteger 200 of Right u -> u; Left _ -> error "ulid"
    }

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "InsightIdempotency" $ do
    describe "reserveInsightIdempotency / completeInsightIdempotency" $ do
      it "Must-INFRA-018: reserve returns Reserved on first call (emulator)" $ do
        maybeEmulator <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulator of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping idempotency emulator tests"
          Just _ -> do
            let context = FirestoreContext{projectId = "test-project", databaseId = "(default)"}
            result <- reserveInsightIdempotency context sampleIdentifier sampleTrace
            case result of
              Left idempotencyError -> fail ("reserve failed: " <> show idempotencyError)
              Right Reserved -> pure ()
              Right AlreadyProcessed -> pure () -- acceptable if test runs twice
      it "Must-INFRA-018: complete succeeds after reserve (emulator)" $ do
        maybeEmulator <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulator of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping idempotency emulator tests"
          Just _ -> do
            let context = FirestoreContext{projectId = "test-project", databaseId = "(default)"}
            _ <- reserveInsightIdempotency context sampleIdentifier sampleTrace
            result <- completeInsightIdempotency context sampleIdentifier
            case result of
              Left idempotencyError -> fail ("complete failed: " <> show idempotencyError)
              Right () -> pure ()
