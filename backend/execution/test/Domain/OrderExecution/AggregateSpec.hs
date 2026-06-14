module Domain.OrderExecution.AggregateSpec (spec) where

import Data.Either (isLeft)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.Aggregate (
  AttemptResult (..),
  BackoffKind (..),
  BrokerOrder (..),
  ExecutionAttempt (..),
  ExecutionRequest (..),
  ExecutionStatus (..),
  OrderExecution,
  OrderExecutionEvent (..),
  OrderExecutionIdentifier (..),
  OrderSide (..),
  RetryPolicySnapshot (..),
  acceptApprovedOrder,
  defaultRetryPolicy,
  recordBrokerFailure,
  recordBrokerSuccess,
 )
import Domain.OrderExecution.Aggregate qualified as Aggregate
import Domain.OrderExecution.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

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
testRequest = ExecutionRequest{symbol = "1306.T", side = Buy, qty = 100}

testBrokerOrder :: BrokerOrder
testBrokerOrder = BrokerOrder "id-001"

retryableFailure :: ReasonCode -> Aggregate.FailureDetail
retryableFailure code = Aggregate.FailureDetail{reasonCode = code, detail = Nothing, retryable = True}

nonRetryableFailure :: ReasonCode -> Aggregate.FailureDetail
nonRetryableFailure code = Aggregate.FailureDetail{reasonCode = code, detail = Nothing, retryable = False}

mkApproved :: OrderExecution
mkApproved = acceptApprovedOrder testIdentifier testRequest defaultRetryPolicy testTrace

-- | retryable failure を attemptCount まで繰り返し適用するヘルパ。
applyFailures :: Int -> Aggregate.FailureDetail -> OrderExecution -> OrderExecution
applyFailures 0 _ execution = execution
applyFailures n failure execution =
  case recordBrokerFailure failure fixedTime execution of
    Right (updated, _) -> applyFailures (n - 1) failure updated
    Left domainError -> error ("unexpected Left: " <> show domainError)

spec :: Spec
spec =
  describe "Domain.OrderExecution.Aggregate" $ do
    -- Must-02: 識別子型
    describe "OrderExecutionIdentifier / BrokerOrder" $ do
      it "supports equality and ordering" $ do
        OrderExecutionIdentifier (mkULID 1) `shouldBe` OrderExecutionIdentifier (mkULID 1)
        OrderExecutionIdentifier (mkULID 1) `shouldNotBe` OrderExecutionIdentifier (mkULID 2)
        compare (OrderExecutionIdentifier (mkULID 1)) (OrderExecutionIdentifier (mkULID 2)) `shouldBe` LT

      it "BrokerOrder is a distinct identifier type" $ do
        BrokerOrder "id-001" `shouldBe` BrokerOrder "id-001"
        BrokerOrder "id-001" `shouldNotBe` BrokerOrder "id-002"

    -- Must-03: 3値 status
    describe "ExecutionStatus" $ do
      it "has exactly Approved, Executed, Failed" $ do
        Approved `shouldNotBe` Executed
        Executed `shouldNotBe` Failed
        Approved `shouldNotBe` Failed

    -- Must-04: smart constructor
    describe "acceptApprovedOrder (Must-04)" $ do
      it "creates an Approved execution with attemptCount 0" $ do
        let execution = mkApproved
        execution.status `shouldBe` Approved
        execution.identifier `shouldBe` testIdentifier
        execution.attemptCount `shouldBe` 0
        execution.brokerOrder `shouldBe` Nothing
        execution.reasonCode `shouldBe` Nothing
        execution.executedAt `shouldBe` Nothing
        execution.attempts `shouldBe` []

      it "default retry policy is max 3 exponential" $ do
        defaultRetryPolicy.maxAttempts `shouldBe` 3
        defaultRetryPolicy.backoff `shouldBe` Exponential

    -- Must-07 RULE-EX-005 INV-EX-001: success
    describe "recordBrokerSuccess (RULE-EX-005, INV-EX-001)" $ do
      it "transitions Approved -> Executed and stores brokerOrder + executedAt" $ do
        case recordBrokerSuccess testBrokerOrder fixedTime mkApproved of
          Left domainError -> error ("unexpected Left: " <> show domainError)
          Right (updated, _) -> do
            updated.status `shouldBe` Executed
            updated.brokerOrder `shouldBe` Just testBrokerOrder
            updated.executedAt `shouldBe` Just fixedTime
            updated.attemptCount `shouldBe` 1

      it "emits OrderExecutionSucceeded with identifier and trace" $ do
        case recordBrokerSuccess testBrokerOrder fixedTime mkApproved of
          Right (_, [event]) ->
            event
              `shouldBe` OrderExecutionSucceeded
                { identifier = testIdentifier
                , brokerOrder = testBrokerOrder
                , executedAt = fixedTime
                , trace = testTrace
                }
          other -> error ("unexpected: " <> show other)

      it "rejects success when not Approved (Must-10 re-confirm forbidden)" $ do
        case recordBrokerSuccess testBrokerOrder fixedTime mkApproved of
          Right (executed, _) ->
            recordBrokerSuccess testBrokerOrder fixedTime executed `shouldSatisfy` isLeft
          Left domainError -> error ("unexpected Left: " <> show domainError)

    -- Must-08 RULE-EX-004: non-retryable -> immediate FAILED
    describe "recordBrokerFailure non-retryable (RULE-EX-004)" $ do
      it "immediately transitions Approved -> Failed for market closed" $ do
        case recordBrokerFailure (nonRetryableFailure ExecutionMarketClosed) fixedTime mkApproved of
          Left domainError -> error ("unexpected Left: " <> show domainError)
          Right (updated, [event]) -> do
            updated.status `shouldBe` Failed
            updated.reasonCode `shouldBe` Just ExecutionMarketClosed
            event
              `shouldBe` OrderExecutionFailed
                { identifier = testIdentifier
                , reasonCode = ExecutionMarketClosed
                , attempt = 1
                , trace = testTrace
                }
          Right other -> error ("unexpected: " <> show other)

      it "fails immediately for insufficient funds" $ do
        case recordBrokerFailure (nonRetryableFailure ExecutionInsufficientFunds) fixedTime mkApproved of
          Right (updated, _) -> do
            updated.status `shouldBe` Failed
            updated.reasonCode `shouldBe` Just ExecutionInsufficientFunds
          Left domainError -> error ("unexpected Left: " <> show domainError)

    -- Must-08 RULE-EX-003: retryable below max keeps Approved
    describe "recordBrokerFailure retryable (RULE-EX-003)" $ do
      it "keeps Approved and increments attemptCount while below max" $ do
        case recordBrokerFailure (retryableFailure ExecutionBrokerTimeout) fixedTime mkApproved of
          Left domainError -> error ("unexpected Left: " <> show domainError)
          Right (updated, [event]) -> do
            updated.status `shouldBe` Approved
            updated.attemptCount `shouldBe` 1
            updated.reasonCode `shouldBe` Nothing
            event
              `shouldBe` OrderExecutionAttempted
                { identifier = testIdentifier
                , attempt = 1
                , trace = testTrace
                }
          Right other -> error ("unexpected: " <> show other)

      it "records a RetryableFailure attempt entry" $ do
        case recordBrokerFailure (retryableFailure ExecutionBrokerTimeout) fixedTime mkApproved of
          Right (updated, _) -> do
            length updated.attempts `shouldBe` 1
            case updated.attempts of
              [ExecutionAttempt{attempt = a, result = r}] -> do
                a `shouldBe` 1
                r `shouldBe` RetryableFailure
              other -> error ("unexpected attempts: " <> show other)
          Left domainError -> error ("unexpected Left: " <> show domainError)

      it "stops at max 3 attempts and confirms Failed with reasonCode (RULE-EX-003 limit)" $ do
        -- 2 retryable failures keep it Approved (attempt 1, 2), 3rd reaches the limit -> Failed
        let afterTwo = applyFailures 2 (retryableFailure ExecutionBrokerTimeout) mkApproved
        afterTwo.status `shouldBe` Approved
        afterTwo.attemptCount `shouldBe` 2
        case recordBrokerFailure (retryableFailure ExecutionBrokerTimeout) fixedTime afterTwo of
          Left domainError -> error ("unexpected Left: " <> show domainError)
          Right (updated, [event]) -> do
            updated.status `shouldBe` Failed
            updated.attemptCount `shouldBe` 3
            updated.reasonCode `shouldBe` Just ExecutionBrokerTimeout
            event
              `shouldBe` OrderExecutionFailed
                { identifier = testIdentifier
                , reasonCode = ExecutionBrokerTimeout
                , attempt = 3
                , trace = testTrace
                }
          Right other -> error ("unexpected: " <> show other)

      it "rejects failure on a terminal Failed state (Must-10)" $ do
        case recordBrokerFailure (nonRetryableFailure ExecutionMarketClosed) fixedTime mkApproved of
          Right (failed, _) ->
            recordBrokerFailure (nonRetryableFailure ExecutionMarketClosed) fixedTime failed
              `shouldSatisfy` isLeft
          Left domainError -> error ("unexpected Left: " <> show domainError)

    -- Must-11 RULE-EX-008 INV-EX-005: every event carries identifier and trace
    describe "OrderExecutionEvent always carries identifier + trace (RULE-EX-008)" $ do
      it "succeeded / attempted / failed all expose identifier and trace" $ do
        let succeeded = OrderExecutionSucceeded testIdentifier testBrokerOrder fixedTime testTrace
        let attempted = OrderExecutionAttempted testIdentifier 1 testTrace
        let failed = OrderExecutionFailed testIdentifier ExecutionBrokerTimeout 3 testTrace
        succeeded.identifier `shouldBe` testIdentifier
        succeeded.trace `shouldBe` testTrace
        attempted.identifier `shouldBe` testIdentifier
        attempted.trace `shouldBe` testTrace
        failed.identifier `shouldBe` testIdentifier
        failed.trace `shouldBe` testTrace

    -- Must-04 §4.1 immutability: identifier unchanged after commands
    describe "identifier immutability" $ do
      it "identifier is unchanged after success" $ do
        case recordBrokerSuccess testBrokerOrder fixedTime mkApproved of
          Right (updated, _) -> updated.identifier `shouldBe` testIdentifier
          Left domainError -> error ("unexpected Left: " <> show domainError)

      it "identifier is unchanged after failure" $ do
        case recordBrokerFailure (retryableFailure ExecutionBrokerTimeout) fixedTime mkApproved of
          Right (updated, _) -> updated.identifier `shouldBe` testIdentifier
          Left domainError -> error ("unexpected Left: " <> show domainError)
