module Infrastructure.Repository.FirestoreOrderExecutionRepositorySpec (spec) where

import Data.Time (UTCTime (..), fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.Aggregate (
  ExecutionRequest (..),
  ExecutionStatus (..),
  OrderExecutionIdentifier (..),
  OrderExecutionRepository (..),
  acceptApprovedOrder,
  recordBrokerFailure,
  recordBrokerSuccess,
 )
import Domain.OrderExecution.ReasonCode (ReasonCode (..))
import Infrastructure.Repository.FirestoreOrderExecutionRepository (
  FirestoreOrderExecutionEnv (..),
  OrderExecutionDocument (..),
  documentToExecution,
  isRetryableForPersist,
  runFirestoreOrderExecutionRepositoryT,
  toDocument,
 )
import Persistence.Firestore (FirestoreContext (..), FirestoreError (..))
import System.Environment (lookupEnv)
import Test.Hspec (Spec, describe, it, pendingWith, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
  describe "FirestoreOrderExecutionRepositoryT" $ do
    -- Pure retry predicate tests
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

    -- TST-INFRA-001: toDocument + documentToExecution round-trip for APPROVED status
    describe "TST-INFRA-001: codec round-trip for APPROVED status" $ do
      it "toDocument then documentToExecution preserves status=Approved" $ do
        let executionIdentifier = OrderExecutionIdentifier{value = testUlid}
            traceValue = Trace{value = testUlid}
            executionRequest = ExecutionRequest{symbol = "1306.T", side = "BUY", qty = 100}
            (execution, _) = acceptApprovedOrder executionIdentifier executionRequest traceValue
            now = UTCTime (fromGregorian 2026 1 15) 0
            document = toDocument now execution
        case documentToExecution document of
          Left errorMessage -> fail ("documentToExecution failed: " <> show errorMessage)
          Right roundTripped -> roundTripped.status `shouldBe` Approved

    -- TST-INFRA-002: round-trip for EXECUTED status (with brokerOrder and executedAt)
    describe "TST-INFRA-002: codec round-trip for EXECUTED status" $ do
      it "toDocument then documentToExecution preserves status=Executed with brokerOrder and executedAt" $ do
        let executionIdentifier = OrderExecutionIdentifier{value = testUlid}
            traceValue = Trace{value = testUlid}
            executionRequest = ExecutionRequest{symbol = "1306.T", side = "BUY", qty = 100}
            (baseExecution, _) = acceptApprovedOrder executionIdentifier executionRequest traceValue
            executedAt = UTCTime (fromGregorian 2026 1 15) 3600
            now = UTCTime (fromGregorian 2026 1 15) 0
        case recordBrokerSuccess "broker-order-001" executedAt baseExecution of
          Left domainError -> fail ("recordBrokerSuccess failed: " <> show domainError)
          Right (executedExecution, _) -> do
            let document = toDocument now executedExecution
            case documentToExecution document of
              Left errorMessage -> fail ("documentToExecution failed: " <> show errorMessage)
              Right roundTripped -> do
                roundTripped.status `shouldBe` Executed
                roundTripped.brokerOrder `shouldBe` Just "broker-order-001"
                roundTripped.executedAt `shouldSatisfy` (/= Nothing)

    -- TST-INFRA-003: codec round-trip for FAILED status with reasonCode
    describe "TST-INFRA-003: codec round-trip for FAILED status with reasonCode" $ do
      it "toDocument then documentToExecution preserves status=Failed and reasonCode" $ do
        let executionIdentifier = OrderExecutionIdentifier{value = testUlid}
            traceValue = Trace{value = testUlid}
            executionRequest = ExecutionRequest{symbol = "1306.T", side = "BUY", qty = 100}
            (baseExecution, _) = acceptApprovedOrder executionIdentifier executionRequest traceValue
            now = UTCTime (fromGregorian 2026 1 15) 0
            -- Force immediate failure: non-retryable reason code, attempt count already at max
            failedBase =
              baseExecution
        case recordBrokerFailure ExecutionMarketClosed Nothing now failedBase of
          Left domainError -> fail ("recordBrokerFailure failed: " <> show domainError)
          Right (failedExecution, _) -> do
            let document = toDocument now failedExecution
            case documentToExecution document of
              Left errorMessage -> fail ("documentToExecution failed: " <> show errorMessage)
              Right roundTripped -> do
                roundTripped.status `shouldBe` Failed
                roundTripped.reasonCode `shouldSatisfy` (/= Nothing)

    -- TST-INFRA-007: emulator round-trip persistExecution -> findExecution
    describe "TST-INFRA-007: persistExecution -> findExecution round-trip" $ do
      it "persists and finds OrderExecution by identifier" $ do
        maybeEmulator <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulator of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore emulator tests"
          Just _ -> do
            let context = FirestoreContext{projectId = "test-project", databaseId = "(default)"}
                environment = FirestoreOrderExecutionEnv{firestoreContext = context}
                executionIdentifier = OrderExecutionIdentifier{value = testUlid}
                traceValue = Trace{value = testUlid}
                executionRequest = ExecutionRequest{symbol = "1306.T", side = "BUY", qty = 100}
                (execution, _) = acceptApprovedOrder executionIdentifier executionRequest traceValue
            runFirestoreOrderExecutionRepositoryT environment $
              persistExecution execution
            result <-
              runFirestoreOrderExecutionRepositoryT environment $
                findExecution executionIdentifier
            case result of
              Nothing -> fail "expected Just OrderExecution"
              Just found -> found.status `shouldBe` Approved

    -- TST-INFRA-008: emulator persistExecution -> findExecutionsByStatus
    describe "TST-INFRA-008: persistExecution -> findExecutionsByStatus Approved" $ do
      it "persists and finds OrderExecution in status list" $ do
        maybeEmulator <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulator of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore emulator tests"
          Just _ -> do
            let context = FirestoreContext{projectId = "test-project", databaseId = "(default)"}
                environment = FirestoreOrderExecutionEnv{firestoreContext = context}
                executionIdentifier = OrderExecutionIdentifier{value = testUlid}
                traceValue = Trace{value = testUlid}
                executionRequest = ExecutionRequest{symbol = "1306.T", side = "BUY", qty = 100}
                (execution, _) = acceptApprovedOrder executionIdentifier executionRequest traceValue
            runFirestoreOrderExecutionRepositoryT environment $
              persistExecution execution
            results <-
              runFirestoreOrderExecutionRepositoryT environment $
                findExecutionsByStatus Approved
            let identifiers = map (.identifier) results
            identifiers `shouldSatisfy` elem executionIdentifier

    -- TST-INFRA-009: idempotency double-reserve integration test (emulator gated)
    describe "TST-INFRA-009: idempotency double-reserve" $ do
      it "second reserve for the same identifier returns AlreadyReserved" $ do
        maybeEmulator <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulator of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore emulator tests"
          Just _ ->
            pendingWith "TST-INFRA-009: integration test not yet implemented — requires FirestoreIdempotencyRepositoryT wiring"

    -- TST-INFRA-010: complete then re-reserve integration test (emulator gated)
    describe "TST-INFRA-010: complete then re-reserve" $ do
      it "re-reserve after complete returns AlreadyProcessed" $ do
        maybeEmulator <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulator of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping Firestore emulator tests"
          Just _ ->
            pendingWith "TST-INFRA-010: integration test not yet implemented — requires FirestoreIdempotencyRepositoryT wiring"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 7 of
  Right ulid -> ulid
  Left _ -> error "test ulid"
