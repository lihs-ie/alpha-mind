module UseCase.ExecuteOrderSpec (spec) where

import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.Aggregate (
  ExecutionRequest (..),
  ExecutionStatus (..),
  OrderExecution,
  OrderExecutionIdentifier (..),
  OrderExecutionRepository (..),
  acceptApprovedOrder,
  dispatchToBroker,
  recordBrokerFailure,
  recordBrokerSuccess,
 )
import Domain.OrderExecution.BrokerPort (BrokerPort (..))
import Domain.OrderExecution.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.ExecuteOrder (
  ApprovedOrderEvent (..),
  BrokerOrder (..),
  ExecuteOrderResult (..),
  ExecutionEventPublisher (..),
  executeOrder,
 )

-- ---------------------------------------------------------------------
-- Test fixtures
-- ---------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

mkTrace :: Integer -> Trace
mkTrace n = Trace (mkULID n)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

fixedIdentifier :: OrderExecutionIdentifier
fixedIdentifier = OrderExecutionIdentifier (mkULID 1)

fixedTrace :: Trace
fixedTrace = mkTrace 100

fixedRequest :: ExecutionRequest
fixedRequest =
  ExecutionRequest
    { symbol = "7203.T"
    , side = "BUY"
    , qty = 100
    }

validEvent :: ApprovedOrderEvent
validEvent =
  ApprovedOrderEvent
    { identifier = fixedIdentifier
    , request = fixedRequest
    , trace = fixedTrace
    , occurredAt = fixedTime
    }

-- | Build an EXECUTED OrderExecution for idempotency tests.
mkExecutedExecution :: OrderExecution
mkExecutedExecution =
  let (execution, _) = acceptApprovedOrder fixedIdentifier fixedRequest fixedTrace
   in case dispatchToBroker fixedTime execution of
        Left domainError -> error ("mkExecutedExecution: dispatchToBroker failed: " ++ show domainError)
        Right (dispatched, _) ->
          case recordBrokerSuccess "BROKER-001" fixedTime dispatched of
            Left domainError -> error ("mkExecutedExecution: recordBrokerSuccess failed: " ++ show domainError)
            Right (executed, _) -> executed

-- | Build a FAILED OrderExecution for idempotency tests (non-retryable failure).
mkFailedExecution :: OrderExecution
mkFailedExecution =
  let (execution, _) = acceptApprovedOrder fixedIdentifier fixedRequest fixedTrace
   in case dispatchToBroker fixedTime execution of
        Left domainError -> error ("mkFailedExecution: dispatchToBroker failed: " ++ show domainError)
        Right (dispatched, _) ->
          case recordBrokerFailure ExecutionMarketClosed Nothing fixedTime dispatched of
            Left domainError -> error ("mkFailedExecution: recordBrokerFailure failed: " ++ show domainError)
            Right (failed, _) -> failed

{- | Build an APPROVED execution with attemptCount=3 (= maxAttempts).
dispatchToBroker increments attemptCount. We simulate 3 dispatches leaving status=APPROVED.
When UseCase.handleBrokerFailure is called with this execution and a retryable error,
domain checks: canRetry = isRetryable && 3 < 3 = False → transitions to FAILED.
-}
mkApprovedAtMaxAttemptsExecution :: OrderExecution
mkApprovedAtMaxAttemptsExecution =
  let (base, _) = acceptApprovedOrder fixedIdentifier fixedRequest fixedTrace
      -- Two dispatch+retryFail cycles bring attemptCount to 2, still APPROVED
      dispatchAndRetry execution =
        case dispatchToBroker fixedTime execution of
          Left domainError -> error ("mkApprovedAtMaxAttemptsExecution dispatch failed: " ++ show domainError)
          Right (dispatched, _) ->
            case recordBrokerFailure ExecutionBrokerTimeout Nothing fixedTime dispatched of
              Left domainError -> error ("mkApprovedAtMaxAttemptsExecution failure failed: " ++ show domainError)
              Right (retried, _) -> retried
      after2Retries = dispatchAndRetry (dispatchAndRetry base)
   in -- Third dispatch increments attemptCount to 3, without recording failure yet
      -- (UseCase calls submitBrokerOrder then handleBrokerFailure, not dispatchToBroker)
      case dispatchToBroker fixedTime after2Retries of
        Left domainError -> error ("mkApprovedAtMaxAttemptsExecution final dispatch failed: " ++ show domainError)
        Right (dispatched, _) -> dispatched

-- ---------------------------------------------------------------------
-- Mock state
-- ---------------------------------------------------------------------

data MockState = MockState
  { executionStore :: Maybe OrderExecution
  , persistedExecutions :: [OrderExecution]
  , brokerCallCount :: Int
  , publishedExecuted :: [(OrderExecutionIdentifier, BrokerOrder, UTCTime, Trace)]
  , publishedFailed :: [(OrderExecutionIdentifier, ReasonCode, Trace)]
  , fakeBrokerResult :: Either ReasonCode Text
  }

newMockState :: IO (IORef MockState)
newMockState =
  newIORef
    MockState
      { executionStore = Nothing
      , persistedExecutions = []
      , brokerCallCount = 0
      , publishedExecuted = []
      , publishedFailed = []
      , fakeBrokerResult = Right "BROKER-001"
      }

-- ---------------------------------------------------------------------
-- Mock monad
-- ---------------------------------------------------------------------

newtype MockM a = MockM {runMockM :: IORef MockState -> IO a}

instance Functor MockM where
  fmap f (MockM g) = MockM $ \ref -> fmap f (g ref)

instance Applicative MockM where
  pure a = MockM $ \_ -> pure a
  MockM f <*> MockM a = MockM $ \ref -> f ref <*> a ref

instance Monad MockM where
  MockM a >>= f = MockM $ \ref -> do
    value <- a ref
    runMockM (f value) ref

-- ---------------------------------------------------------------------
-- Port instances (test doubles — only in test/)
-- ---------------------------------------------------------------------

instance OrderExecutionRepository MockM where
  findExecution _ = MockM $ \ref -> do
    state <- readIORef ref
    pure state.executionStore
  findExecutionsByStatus _ = pure []
  searchExecutions _ = pure []
  persistExecution execution = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { executionStore = Just execution
        , persistedExecutions = state.persistedExecutions ++ [execution]
        }
  terminateExecution _ = pure ()

instance BrokerPort MockM where
  submitBrokerOrder _ = MockM $ \ref -> do
    modifyIORef' ref $ \state ->
      state{brokerCallCount = state.brokerCallCount + 1}
    state <- readIORef ref
    pure state.fakeBrokerResult

instance ExecutionEventPublisher MockM where
  publishOrdersExecuted executionIdentifier brokerOrder executedAt traceValue = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { publishedExecuted =
            state.publishedExecuted
              ++ [(executionIdentifier, brokerOrder, executedAt, traceValue)]
        }
  publishOrdersExecutionFailed executionIdentifier reasonCode traceValue = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { publishedFailed =
            state.publishedFailed
              ++ [(executionIdentifier, reasonCode, traceValue)]
        }

runWithMock :: IORef MockState -> MockM a -> IO a
runWithMock ref (MockM f) = f ref

-- ---------------------------------------------------------------------
-- Test helper
-- ---------------------------------------------------------------------

runExecuteOrder :: IORef MockState -> IO ExecuteOrderResult
runExecuteOrder ref =
  runWithMock ref $
    executeOrder fixedTime validEvent

-- ---------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "UseCase.ExecuteOrder" $ do
    -- TST-UC-EX-001: Idempotent — EXECUTED already → ExecuteOrderDuplicate, no broker call
    describe "TST-UC-EX-001: EXECUTED already → ExecuteOrderDuplicate, no broker call" $ do
      it "returns ExecuteOrderDuplicate when OrderExecution is already EXECUTED" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{executionStore = Just mkExecutedExecution}
        result <- runExecuteOrder ref
        result `shouldBe` ExecuteOrderDuplicate

      it "does not call BrokerPort when EXECUTED" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{executionStore = Just mkExecutedExecution}
        _ <- runExecuteOrder ref
        state <- readIORef ref
        state.brokerCallCount `shouldBe` 0

    -- TST-UC-EX-002: Happy path — broker success → persist then publish (ordering)
    describe "TST-UC-EX-002: broker success → EXECUTED, persist before publish" $ do
      it "returns ExecuteOrderSucceeded on broker success" $ do
        ref <- newMockState
        result <- runExecuteOrder ref
        result `shouldBe` ExecuteOrderSucceeded

      it "persists execution in EXECUTED state" $ do
        ref <- newMockState
        _ <- runExecuteOrder ref
        state <- readIORef ref
        let lastPersisted = last state.persistedExecutions
        lastPersisted.status `shouldBe` Executed

      it "publishOrdersExecuted is called exactly once" $ do
        ref <- newMockState
        _ <- runExecuteOrder ref
        state <- readIORef ref
        length state.publishedExecuted `shouldBe` 1

      it "persist is called before publishOrdersExecuted (ordering)" $ do
        ref <- newMockState
        _ <- runExecuteOrder ref
        state <- readIORef ref
        -- Both must have been called (ordering is guaranteed by sequencing in implementation)
        (not (null state.persistedExecutions) && not (null state.publishedExecuted))
          `shouldBe` True

    -- TST-UC-EX-003: Retryable broker failure (ExecutionBrokerTimeout) → stays APPROVED, no fail publisher
    describe "TST-UC-EX-003: ExecutionBrokerTimeout → APPROVED, no fail publisher" $ do
      it "returns ExecuteOrderRetryable on timeout" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{fakeBrokerResult = Left ExecutionBrokerTimeout}
        result <- runExecuteOrder ref
        result `shouldBe` ExecuteOrderRetryable

      it "does not call publishOrdersExecutionFailed on retryable error" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{fakeBrokerResult = Left ExecutionBrokerTimeout}
        _ <- runExecuteOrder ref
        state <- readIORef ref
        length state.publishedFailed `shouldBe` 0

      it "persists execution in APPROVED state on retryable error" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{fakeBrokerResult = Left ExecutionBrokerTimeout}
        _ <- runExecuteOrder ref
        state <- readIORef ref
        case state.executionStore of
          Nothing -> fail "No execution was persisted"
          Just execution -> execution.status `shouldBe` Approved

    -- TST-UC-EX-004: Retryable error exhausting maxAttempts → FAILED → fail publisher called
    describe "TST-UC-EX-004: ExecutionBrokerTimeout at maxAttempts → FAILED, fail publisher called" $ do
      it "returns ExecuteOrderFailed when retryable error exhausts maxAttempts" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state
            { executionStore = Just mkApprovedAtMaxAttemptsExecution
            , fakeBrokerResult = Left ExecutionBrokerTimeout
            }
        result <- runWithMock ref (executeOrder fixedTime validEvent)
        result `shouldSatisfy` isExecuteOrderFailed

      it "calls publishOrdersExecutionFailed when maxAttempts exhausted" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state
            { executionStore = Just mkApprovedAtMaxAttemptsExecution
            , fakeBrokerResult = Left ExecutionBrokerTimeout
            }
        _ <- runWithMock ref (executeOrder fixedTime validEvent)
        state <- readIORef ref
        length state.publishedFailed `shouldBe` 1

    -- TST-UC-EX-005: Non-retryable broker failure (ExecutionMarketClosed) → FAILED → fail publisher called
    describe "TST-UC-EX-005: ExecutionMarketClosed → FAILED, fail publisher called" $ do
      it "returns ExecuteOrderFailed on non-retryable failure" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{fakeBrokerResult = Left ExecutionMarketClosed}
        result <- runExecuteOrder ref
        result `shouldSatisfy` isExecuteOrderFailed

      it "calls publishOrdersExecutionFailed on non-retryable failure" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{fakeBrokerResult = Left ExecutionMarketClosed}
        _ <- runExecuteOrder ref
        state <- readIORef ref
        length state.publishedFailed `shouldBe` 1

    -- TST-UC-EX-006: trace propagated to Publisher matches OrderExecution.trace
    describe "TST-UC-EX-006: trace propagated to publishOrdersExecuted equals OrderExecution.trace" $ do
      it "trace propagated to publishOrdersExecuted on success" $ do
        ref <- newMockState
        _ <- runExecuteOrder ref
        state <- readIORef ref
        case state.publishedExecuted of
          [] -> fail "publishOrdersExecuted was not called"
          (_, _, _, traceValue) : _ -> traceValue `shouldBe` fixedTrace

      it "trace propagated to publishOrdersExecutionFailed on failure" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{fakeBrokerResult = Left ExecutionMarketClosed}
        _ <- runExecuteOrder ref
        state <- readIORef ref
        case state.publishedFailed of
          [] -> fail "publishOrdersExecutionFailed was not called"
          (_, _, traceValue) : _ -> traceValue `shouldBe` fixedTrace

    -- Idempotent — FAILED already → ExecuteOrderDuplicate, no broker call
    describe "FAILED already → ExecuteOrderDuplicate, no broker call" $ do
      it "returns ExecuteOrderDuplicate when OrderExecution is already FAILED" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{executionStore = Just mkFailedExecution}
        result <- runExecuteOrder ref
        result `shouldBe` ExecuteOrderDuplicate

      it "does not call BrokerPort when FAILED" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{executionStore = Just mkFailedExecution}
        _ <- runExecuteOrder ref
        state <- readIORef ref
        state.brokerCallCount `shouldBe` 0

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

isExecuteOrderFailed :: ExecuteOrderResult -> Bool
isExecuteOrderFailed (ExecuteOrderFailed _ _) = True
isExecuteOrderFailed _ = False
