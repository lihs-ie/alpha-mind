module Domain.OrderExecution.AggregateSpec (spec) where

import Data.Either (isLeft)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.Aggregate (
  ApprovedStatusSpecification (..),
  ExecutionRequest (..),
  ExecutionStatus (..),
  FailureDetail (..),
  OrderExecution,
  OrderExecutionEvent (..),
  OrderExecutionIdentifier (..),
  RetryableFailureSpecification (..),
  acceptApprovedOrder,
  dispatchToBroker,
  isSatisfiedBy,
  recordBrokerFailure,
  recordBrokerSuccess,
 )
import Domain.OrderExecution.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

testIdentifier :: OrderExecutionIdentifier
testIdentifier = OrderExecutionIdentifier (mkULID 1)

testTrace :: Trace
testTrace = Trace (mkULID 100)

testRequest :: ExecutionRequest
testRequest =
  ExecutionRequest
    { symbol = "7203.T"
    , side = "BUY"
    , qty = 100
    }

mkApprovedExecution :: (OrderExecution, [OrderExecutionEvent])
mkApprovedExecution = acceptApprovedOrder testIdentifier testRequest testTrace

spec :: Spec
spec =
  describe "Domain.OrderExecution.Aggregate" $ do
    -- TST-EX-001: status != APPROVED → dispatchToBroker returns Left;
    --             ApprovedStatusSpecification.isSatisfiedBy returns False for non-APPROVED
    describe "TST-EX-001: dispatchToBroker rejects non-APPROVED status" $ do
      it "FAILED status is rejected by dispatchToBroker" $ do
        let (execution, _) = mkApprovedExecution
        -- transition to FAILED via non-retryable error
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right from first dispatch"
          Right (dispatched, _) ->
            case recordBrokerFailure ExecutionBrokerRejected Nothing fixedTime dispatched of
              Left _ -> fail "Expected Right from recordBrokerFailure"
              Right (failed, _) -> do
                isSatisfiedBy (ApprovedStatusSpecification ()) failed `shouldBe` False
                dispatchToBroker fixedTime failed `shouldSatisfy` isLeft

      it "EXECUTED status is rejected by dispatchToBroker" $ do
        let (execution, _) = mkApprovedExecution
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right from first dispatch"
          Right (dispatched, _) ->
            case recordBrokerSuccess "BROKER-001" fixedTime dispatched of
              Left _ -> fail "Expected Right from recordBrokerSuccess"
              Right (executed, _) -> do
                isSatisfiedBy (ApprovedStatusSpecification ()) executed `shouldBe` False
                dispatchToBroker fixedTime executed `shouldSatisfy` isLeft

    -- TST-EX-002: EXECUTED state → isDuplicateDispatch returns True
    describe "TST-EX-002: EXECUTED/FAILED state → duplicate dispatch detected" $ do
      it "EXECUTED execution is flagged as duplicate" $ do
        let (execution, _) = mkApprovedExecution
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right"
          Right (dispatched, _) ->
            case recordBrokerSuccess "BROKER-001" fixedTime dispatched of
              Left _ -> fail "Expected Right"
              Right (executed, _) -> do
                executed.status `shouldBe` Executed
                -- dispatchToBroker returns Left for EXECUTED
                dispatchToBroker fixedTime executed `shouldSatisfy` isLeft

      it "FAILED execution is flagged as duplicate" $ do
        let (execution, _) = mkApprovedExecution
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right"
          Right (dispatched, _) ->
            case recordBrokerFailure ExecutionBrokerRejected Nothing fixedTime dispatched of
              Left _ -> fail "Expected Right"
              Right (failed, _) -> do
                failed.status `shouldBe` Failed
                dispatchToBroker fixedTime failed `shouldSatisfy` isLeft

    -- TST-EX-003: retryable error + attemptCount < 3 → stays APPROVED, increments attemptCount
    describe "TST-EX-003: retryable error with attemptCount < maxAttempts stays APPROVED" $ do
      it "retryable error at attempt 1 keeps status APPROVED" $ do
        let (execution, _) = mkApprovedExecution
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right from dispatch"
          Right (dispatched, _) ->
            case recordBrokerFailure ExecutionBrokerTimeout Nothing fixedTime dispatched of
              Left _ -> fail "Expected Right from recordBrokerFailure"
              Right (retried, _) -> do
                retried.status `shouldBe` Approved
                retried.attemptCount `shouldBe` 1

      it "retryable error 3 times transitions to FAILED with attemptCount = 3" $ do
        let (execution, _) = mkApprovedExecution
        -- attempt 1
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right dispatch 1"
          Right (dispatched1, _) ->
            case recordBrokerFailure ExecutionBrokerTimeout Nothing fixedTime dispatched1 of
              Left _ -> fail "Expected Right failure 1"
              Right (afterFailure1, _) ->
                -- attempt 2
                case dispatchToBroker fixedTime afterFailure1 of
                  Left _ -> fail "Expected Right dispatch 2"
                  Right (dispatched2, _) ->
                    case recordBrokerFailure ExecutionBrokerTimeout Nothing fixedTime dispatched2 of
                      Left _ -> fail "Expected Right failure 2"
                      Right (afterFailure2, _) ->
                        -- attempt 3
                        case dispatchToBroker fixedTime afterFailure2 of
                          Left _ -> fail "Expected Right dispatch 3"
                          Right (dispatched3, _) ->
                            case recordBrokerFailure ExecutionBrokerTimeout Nothing fixedTime dispatched3 of
                              Left _ -> fail "Expected Right failure 3"
                              Right (finalExecution, events) -> do
                                finalExecution.status `shouldBe` Failed
                                finalExecution.attemptCount `shouldBe` 3
                                events `shouldSatisfy` (not . null)

    -- TST-EX-004: non-retryable error → immediately FAILED with reasonCode;
    --             RetryableFailureSpecification.isSatisfiedBy returns False for non-retryable codes
    describe "TST-EX-004: non-retryable error immediately transitions to FAILED" $ do
      it "EXECUTION_BROKER_REJECTED causes immediate FAILED" $ do
        let (execution, _) = mkApprovedExecution
        let nonRetryableFailure = FailureDetail{reasonCode = ExecutionBrokerRejected, detail = Nothing, retryable = False}
        isSatisfiedBy (RetryableFailureSpecification ()) nonRetryableFailure `shouldBe` False
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right dispatch"
          Right (dispatched, _) ->
            case recordBrokerFailure ExecutionBrokerRejected Nothing fixedTime dispatched of
              Left _ -> fail "Expected Right failure"
              Right (failed, _) -> do
                failed.status `shouldBe` Failed
                failed.reasonCode `shouldBe` Just ExecutionBrokerRejected

      it "EXECUTION_MARKET_CLOSED causes immediate FAILED" $ do
        let (execution, _) = mkApprovedExecution
        let nonRetryableFailure = FailureDetail{reasonCode = ExecutionMarketClosed, detail = Nothing, retryable = False}
        isSatisfiedBy (RetryableFailureSpecification ()) nonRetryableFailure `shouldBe` False
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right dispatch"
          Right (dispatched, _) ->
            case recordBrokerFailure ExecutionMarketClosed Nothing fixedTime dispatched of
              Left _ -> fail "Expected Right failure"
              Right (failed, _) -> do
                failed.status `shouldBe` Failed
                failed.reasonCode `shouldBe` Just ExecutionMarketClosed

      it "EXECUTION_INSUFFICIENT_FUNDS causes immediate FAILED" $ do
        let (execution, _) = mkApprovedExecution
        let nonRetryableFailure = FailureDetail{reasonCode = ExecutionInsufficientFunds, detail = Nothing, retryable = False}
        isSatisfiedBy (RetryableFailureSpecification ()) nonRetryableFailure `shouldBe` False
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right dispatch"
          Right (dispatched, _) ->
            case recordBrokerFailure ExecutionInsufficientFunds Nothing fixedTime dispatched of
              Left _ -> fail "Expected Right failure"
              Right (failed, _) ->
                failed.status `shouldBe` Failed

    -- TST-EX-005: recordBrokerSuccess → status=EXECUTED, emits OrderExecutionSucceeded
    describe "TST-EX-005: recordBrokerSuccess emits OrderExecutionSucceeded" $ do
      it "emits OrderExecutionSucceeded with brokerOrder, executedAt, trace" $ do
        let (execution, _) = mkApprovedExecution
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right dispatch"
          Right (dispatched, _) ->
            case recordBrokerSuccess "BROKER-XYZ" fixedTime dispatched of
              Left _ -> fail "Expected Right success"
              Right (executed, events) -> do
                executed.status `shouldBe` Executed
                executed.brokerOrder `shouldBe` Just "BROKER-XYZ"
                executed.executedAt `shouldBe` Just fixedTime
                case events of
                  [OrderExecutionSucceeded{brokerOrder = bo, executedAt = ea, trace = tr}] -> do
                    bo `shouldBe` "BROKER-XYZ"
                    ea `shouldBe` fixedTime
                    tr `shouldBe` testTrace
                  _ -> fail ("Expected exactly 1 OrderExecutionSucceeded, got " ++ show (length events))

    -- TST-EX-006: recordBrokerFailure final → status=FAILED, emits OrderExecutionFailed
    describe "TST-EX-006: final failure emits OrderExecutionFailed with reasonCode" $ do
      it "non-retryable failure emits OrderExecutionFailed with reasonCode" $ do
        let (execution, _) = mkApprovedExecution
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right dispatch"
          Right (dispatched, _) ->
            case recordBrokerFailure ExecutionBrokerRejected (Just "order rejected") fixedTime dispatched of
              Left _ -> fail "Expected Right failure"
              Right (_, events) ->
                case events of
                  [OrderExecutionFailed{reasonCode = code, trace = tr}] -> do
                    code `shouldBe` ExecutionBrokerRejected
                    tr `shouldBe` testTrace
                  _ -> fail ("Expected exactly 1 OrderExecutionFailed, got " ++ show (length events))

    -- TST-EX-008: all events contain trace and identifier fields
    describe "TST-EX-008: domain events contain trace and identifier" $ do
      it "OrderExecutionAttempted carries trace and identifier" $ do
        let (execution, _) = mkApprovedExecution
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right dispatch"
          Right (_, events) ->
            case events of
              [OrderExecutionAttempted{identifier = eid, trace = tr}] -> do
                eid `shouldBe` testIdentifier
                tr `shouldBe` testTrace
              _ -> fail ("Expected 1 OrderExecutionAttempted, got " ++ show (length events))

      it "OrderExecutionSucceeded carries trace and identifier" $ do
        let (execution, _) = mkApprovedExecution
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right dispatch"
          Right (dispatched, _) ->
            case recordBrokerSuccess "BROKER-001" fixedTime dispatched of
              Left _ -> fail "Expected Right success"
              Right (_, events) ->
                case events of
                  [OrderExecutionSucceeded{identifier = eid, trace = tr}] -> do
                    eid `shouldBe` testIdentifier
                    tr `shouldBe` testTrace
                  _ -> fail ("Expected 1 OrderExecutionSucceeded, got " ++ show (length events))

      it "OrderExecutionFailed carries trace and identifier" $ do
        let (execution, _) = mkApprovedExecution
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right dispatch"
          Right (dispatched, _) ->
            case recordBrokerFailure ExecutionBrokerRejected Nothing fixedTime dispatched of
              Left _ -> fail "Expected Right failure"
              Right (_, events) ->
                case events of
                  [OrderExecutionFailed{identifier = eid, trace = tr}] -> do
                    eid `shouldBe` testIdentifier
                    tr `shouldBe` testTrace
                  _ -> fail ("Expected 1 OrderExecutionFailed, got " ++ show (length events))

    -- TST-EX-009: no Id suffix in identifier type names (compile-time verification)
    describe "TST-EX-009: identifier naming convention" $ do
      it "OrderExecutionIdentifier does not use Id suffix (compile-time proof)" $ do
        -- The type name itself confirms compliance; this test existing means it compiled.
        let executionIdentifier = OrderExecutionIdentifier (mkULID 42)
        executionIdentifier `shouldBe` OrderExecutionIdentifier (mkULID 42)

    -- Additional: acceptApprovedOrder creates APPROVED status
    describe "acceptApprovedOrder" $ do
      it "creates an APPROVED execution with given identifier" $ do
        let (execution, _) = mkApprovedExecution
        execution.status `shouldBe` Approved
        execution.identifier `shouldBe` testIdentifier
        execution.attemptCount `shouldBe` 0
        execution.brokerOrder `shouldBe` Nothing
        execution.reasonCode `shouldBe` Nothing

      it "identifier is immutable through commands" $ do
        let (execution, _) = mkApprovedExecution
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right"
          Right (dispatched, _) ->
            case recordBrokerSuccess "BROKER-001" fixedTime dispatched of
              Left _ -> fail "Expected Right"
              Right (executed, _) ->
                executed.identifier `shouldBe` testIdentifier
