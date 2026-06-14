module UseCase.ExecuteOrder (
  -- * Ports
  ExecutionEventPublisher (..),

  -- * UseCase-layer types
  BrokerOrder (..),

  -- * Input type
  ApprovedOrderEvent (..),

  -- * Result type
  ExecuteOrderResult (..),

  -- * Use case
  executeOrder,
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.Aggregate (
  ExecutionRequest (..),
  OrderExecution,
  OrderExecutionIdentifier (..),
  OrderExecutionRepository (..),
  recordBrokerFailure,
  recordBrokerSuccess,
 )
import Domain.OrderExecution.BrokerExecutionPolicy (isRetryable)
import Domain.OrderExecution.BrokerPort (BrokerPort (..))
import Domain.OrderExecution.ExecutionIdempotencyPolicy (isDuplicateDispatch)
import Domain.OrderExecution.OrderExecutionFactory (fromApprovedOrder)
import Domain.OrderExecution.ReasonCode (ReasonCode (..))

-- ---------------------------------------------------------------------
-- UseCase-layer types
-- ---------------------------------------------------------------------

-- | Broker-side order identifier returned by the broker on success
newtype BrokerOrder = BrokerOrder {value :: Text}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Port: ExecutionEventPublisher
-- ---------------------------------------------------------------------

{- | ExecutionEventPublisher: Pub/Sub へ実行結果イベントを発行する Port。
実装は presentation / infra 層 (Issue #49) に委ねる。
-}
class (Monad m) => ExecutionEventPublisher m where
  publishOrdersExecuted ::
    OrderExecutionIdentifier ->
    BrokerOrder ->
    UTCTime ->
    Trace ->
    m ()
  publishOrdersExecutionFailed ::
    OrderExecutionIdentifier ->
    ReasonCode ->
    Trace ->
    m ()

-- ---------------------------------------------------------------------
-- Input type
-- ---------------------------------------------------------------------

{- | ApprovedOrderEvent: orders.approved イベントペイロードを表す UseCase 層内部型。
Presentation 層から受け取る。
-}
data ApprovedOrderEvent = ApprovedOrderEvent
  { identifier :: OrderExecutionIdentifier
  , request :: ExecutionRequest
  , trace :: Trace
  , occurredAt :: UTCTime
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Result type
-- ---------------------------------------------------------------------

-- | UseCase の結果型。4 ケース。
data ExecuteOrderResult
  = ExecuteOrderSucceeded
  | ExecuteOrderRetryable
  | ExecuteOrderFailed ReasonCode Bool
  | ExecuteOrderDuplicate
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Use case
-- ---------------------------------------------------------------------

{- | UC-EX-01: orders.approved イベントを受信し、ブローカー発注・状態更新・
イベント発行をオーケストレーションする。

処理順序:
1. 冪等性チェック: findExecution identifier
   - 既存で EXECUTED/FAILED → ExecuteOrderDuplicate (BrokerPort を呼ばない)
   - 既存で APPROVED → 重複ディスパッチでなければブローカー呼び出しへ進む
   - 存在しない → fromApprovedOrder で新規作成し persistExecution
2. submitBrokerOrder request via BrokerPort
   - 成功 (Right brokerOrder) → recordBrokerSuccess → persistExecution → publishOrdersExecuted
   - 失敗 (Left reasonCode) → isRetryable 判定:
     retryable かつ attemptCount < maxAttempts → persistExecution (APPROVED) → ExecuteOrderRetryable
     それ以外 → recordBrokerFailure → persistExecution → publishOrdersExecutionFailed → ExecuteOrderFailed
-}
executeOrder ::
  ( Monad m
  , OrderExecutionRepository m
  , BrokerPort m
  , ExecutionEventPublisher m
  ) =>
  UTCTime ->
  ApprovedOrderEvent ->
  m ExecuteOrderResult
executeOrder currentTime event = do
  existingExecution <- findExecution event.identifier
  case existingExecution of
    Just execution
      | isDuplicateDispatch execution ->
          pure ExecuteOrderDuplicate
    Just execution ->
      -- APPROVED but possibly re-dispatched; proceed to broker
      processWithExecution currentTime event execution
    Nothing -> do
      -- New execution: create via factory, persist, then broker
      let (newExecution, _creationEvents) = fromApprovedOrder event.identifier event.request event.trace
      persistExecution newExecution
      processWithExecution currentTime event newExecution

-- | Core dispatch logic given an APPROVED OrderExecution.
processWithExecution ::
  ( Monad m
  , OrderExecutionRepository m
  , BrokerPort m
  , ExecutionEventPublisher m
  ) =>
  UTCTime ->
  ApprovedOrderEvent ->
  OrderExecution ->
  m ExecuteOrderResult
processWithExecution currentTime event execution = do
  brokerResult <- submitBrokerOrder event.request
  case brokerResult of
    Right brokerOrderIdentifier ->
      handleBrokerSuccess currentTime execution brokerOrderIdentifier
    Left reasonCode ->
      handleBrokerFailure currentTime execution reasonCode

-- | Handle successful broker response: record success, persist, publish.
handleBrokerSuccess ::
  ( Monad m
  , OrderExecutionRepository m
  , ExecutionEventPublisher m
  ) =>
  UTCTime ->
  OrderExecution ->
  Text ->
  m ExecuteOrderResult
handleBrokerSuccess currentTime execution brokerOrderIdentifier =
  case recordBrokerSuccess brokerOrderIdentifier currentTime execution of
    Left _domainError ->
      -- Unexpected domain error — treat as internal failure
      pure (ExecuteOrderFailed InternalError False)
    Right (executedExecution, _domainEvents) -> do
      persistExecution executedExecution
      let traceValue = executedExecution.trace
      case executedExecution.executedAt of
        Nothing ->
          pure (ExecuteOrderFailed InternalError False)
        Just executedAtTime -> do
          publishOrdersExecuted
            executedExecution.identifier
            (BrokerOrder brokerOrderIdentifier)
            executedAtTime
            traceValue
          pure ExecuteOrderSucceeded

-- | Handle failed broker response: check retryability, record, persist, optionally publish.
handleBrokerFailure ::
  ( Monad m
  , OrderExecutionRepository m
  , ExecutionEventPublisher m
  ) =>
  UTCTime ->
  OrderExecution ->
  ReasonCode ->
  m ExecuteOrderResult
handleBrokerFailure currentTime execution reasonCode =
  let canRetry = isRetryable reasonCode && execution.attemptCount < execution.maxAttempts
   in if canRetry
        then do
          -- Stay APPROVED; record the failure detail without terminal state transition
          case recordBrokerFailure reasonCode Nothing currentTime execution of
            Left _domainError ->
              pure (ExecuteOrderFailed InternalError False)
            Right (retriedExecution, _domainEvents) -> do
              persistExecution retriedExecution
              pure ExecuteOrderRetryable
        else do
          -- Transition to FAILED
          case recordBrokerFailure reasonCode Nothing currentTime execution of
            Left _domainError ->
              pure (ExecuteOrderFailed InternalError False)
            Right (failedExecution, _domainEvents) -> do
              persistExecution failedExecution
              let traceValue = failedExecution.trace
              publishOrdersExecutionFailed
                failedExecution.identifier
                reasonCode
                traceValue
              pure (ExecuteOrderFailed reasonCode False)
