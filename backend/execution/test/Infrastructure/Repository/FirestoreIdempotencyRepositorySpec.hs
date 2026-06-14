module Infrastructure.Repository.FirestoreIdempotencyRepositorySpec (spec) where

import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.Aggregate (OrderExecutionIdentifier (..))
import Infrastructure.Repository.FirestoreIdempotencyRepository (
  FirestoreIdempotencyEnv (..),
  completeExecutionIdempotency,
  reserveExecutionIdempotency,
  runFirestoreIdempotencyRepositoryT,
 )
import Persistence.Firestore (FirestoreContext (..))
import Persistence.Idempotency (ReserveResult (..))
import System.Environment (lookupEnv)
import Test.Hspec (Spec, describe, it, pendingWith, shouldBe)

spec :: Spec
spec = do
  describe "FirestoreIdempotencyRepositoryT" $ do
    -- TST-INFRA-009: idempotency double-reserve (emulator gated)
    describe "TST-INFRA-009: double-reserve returns AlreadyReserved" $ do
      it "second reserveExecutionIdempotency for the same identifier returns AlreadyReserved" $ do
        maybeEmulator <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulator of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore emulator tests"
          Just _ -> do
            let context = FirestoreContext{projectId = "test-project", databaseId = "(default)"}
                environment = FirestoreIdempotencyEnv{firestoreContext = context, serviceName = "execution"}
                executionIdentifier = OrderExecutionIdentifier{value = testUlid}
                traceValue = Trace{value = testUlid}
            _ <-
              runFirestoreIdempotencyRepositoryT environment $
                reserveExecutionIdempotency executionIdentifier traceValue
            secondResult <-
              runFirestoreIdempotencyRepositoryT environment $
                reserveExecutionIdempotency executionIdentifier traceValue
            case secondResult of
              Left reserveError -> fail ("second reserve failed unexpectedly: " <> show reserveError)
              Right reserveResult -> reserveResult `shouldBe` AlreadyReserved

    -- TST-INFRA-010: complete then re-reserve returns AlreadyProcessed (emulator gated)
    describe "TST-INFRA-010: complete then re-reserve returns AlreadyProcessed" $ do
      it "re-reserve after completeExecutionIdempotency returns AlreadyProcessed" $ do
        maybeEmulator <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulator of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore emulator tests"
          Just _ -> do
            let context = FirestoreContext{projectId = "test-project", databaseId = "(default)"}
                environment = FirestoreIdempotencyEnv{firestoreContext = context, serviceName = "execution"}
                executionIdentifier = OrderExecutionIdentifier{value = testUlid2}
                traceValue = Trace{value = testUlid2}
            _ <-
              runFirestoreIdempotencyRepositoryT environment $
                reserveExecutionIdempotency executionIdentifier traceValue
            _ <-
              runFirestoreIdempotencyRepositoryT environment $
                completeExecutionIdempotency executionIdentifier
            reReserveResult <-
              runFirestoreIdempotencyRepositoryT environment $
                reserveExecutionIdempotency executionIdentifier traceValue
            case reReserveResult of
              Left reserveError -> fail ("re-reserve failed unexpectedly: " <> show reserveError)
              Right reserveResult -> reserveResult `shouldBe` AlreadyProcessed

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 11 of
  Right ulid -> ulid
  Left _ -> error "test ulid"

testUlid2 :: ULID
testUlid2 = case ulidFromInteger 12 of
  Right ulid -> ulid
  Left _ -> error "test ulid2"
