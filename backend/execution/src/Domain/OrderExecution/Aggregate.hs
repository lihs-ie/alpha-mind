{-# LANGUAGE NoFieldSelectors #-}

module Domain.OrderExecution.Aggregate (
  -- * Identifiers
  OrderExecutionIdentifier (..),
  BrokerOrder (..),

  -- * Status enum
  ExecutionStatus (..),

  -- * Value Objects
  OrderSide (..),
  ExecutionRequest (..),
  BackoffKind (..),
  RetryPolicySnapshot (..),
  defaultRetryPolicy,
  FailureDetail (..),
  AttemptResult (..),
  ExecutionAttempt (..),

  -- * Aggregate (construct via 'acceptApprovedOrder' only; constructor hidden)
  OrderExecution,

  -- * Smart constructor
  acceptApprovedOrder,

  -- * Commands
  recordBrokerSuccess,
  recordBrokerFailure,
  terminateExecution,

  -- * Domain Events
  OrderExecutionEvent (..),

  -- * Repository Port
  OrderExecutionSearchCriteria (..),
  emptyOrderExecutionSearchCriteria,
  OrderExecutionRepository (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.OrderExecution (Trace)
import Domain.OrderExecution.Error (DomainError (..))
import Domain.OrderExecution.ReasonCode (ReasonCode)
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- Identifiers
-- ---------------------------------------------------------------------

-- | Must-02: 注文識別子。order_executions/{identifier}。XXXId 表記は禁止。
newtype OrderExecutionIdentifier = OrderExecutionIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- | Must-02: ブローカー側注文識別子。内部 identifier と混同しない（Ubiquitous Language）。
newtype BrokerOrder = BrokerOrder {value :: Text}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------

-- | Must-03: execution 文脈の状態。3値のみ（§4.1.1）。
data ExecutionStatus
  = Approved
  | Executed
  | Failed
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Value Objects
-- ---------------------------------------------------------------------

-- | Must-05: 売買区分。
data OrderSide
  = Buy
  | Sell
  deriving stock (Eq, Ord, Show)

{- | Must-05: ExecutionRequest — 発注要求スナップショット。
コンストラクタを隠蔽せず公開するが、qty は正の数であることを利用側が保証する VO。
-}
data ExecutionRequest = ExecutionRequest
  { symbol :: Text
  , side :: OrderSide
  , qty :: Double
  }
  deriving stock (Eq, Show)

-- | Must-05: バックオフ種別。設計書既定は exponential。
data BackoffKind
  = Exponential
  deriving stock (Eq, Ord, Show)

-- | Must-05: RetryPolicySnapshot — リトライ判定条件のスナップショット。
data RetryPolicySnapshot = RetryPolicySnapshot
  { maxAttempts :: Int
  , backoff :: BackoffKind
  }
  deriving stock (Eq, Show)

-- | 既定リトライポリシー（最大3回・指数バックオフ。execution.json retryPolicy）。
defaultRetryPolicy :: RetryPolicySnapshot
defaultRetryPolicy = RetryPolicySnapshot{maxAttempts = 3, backoff = Exponential}

-- | Must-05: FailureDetail — 最終失敗情報。
data FailureDetail = FailureDetail
  { reasonCode :: ReasonCode
  , detail :: Maybe Text
  , retryable :: Bool
  }
  deriving stock (Eq, Show)

-- | Must-05: 1試行の結果区分（§4.2 ExecutionAttempt）。
data AttemptResult
  = Success
  | RetryableFailure
  | FinalFailure
  deriving stock (Eq, Ord, Show)

-- | Must-05: ExecutionAttempt — 試行履歴エントリ。
data ExecutionAttempt = ExecutionAttempt
  { attempt :: Int
  , attemptedAt :: UTCTime
  , result :: AttemptResult
  , reasonCode :: Maybe ReasonCode
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Domain Events (Must-11)
-- ---------------------------------------------------------------------

{- | Must-11: OrderExecutionEvent — 3バリアント。
全イベントに identifier と trace を含む（RULE-EX-008, INV-EX-005）。
-}
data OrderExecutionEvent
  = OrderExecutionAttempted
      { identifier :: OrderExecutionIdentifier
      , attempt :: Int
      , trace :: Trace
      }
  | OrderExecutionSucceeded
      { identifier :: OrderExecutionIdentifier
      , brokerOrder :: BrokerOrder
      , executedAt :: UTCTime
      , trace :: Trace
      }
  | OrderExecutionFailed
      { identifier :: OrderExecutionIdentifier
      , reasonCode :: ReasonCode
      , attempt :: Int
      , trace :: Trace
      }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Aggregate
--
-- コンストラクタは隠蔽。外部からは acceptApprovedOrder + コマンド関数で操作する。
-- フィールド名は oe プレフィックスで HasField 衝突を回避。
-- ---------------------------------------------------------------------

data OrderExecution = OrderExecution
  { oeIdentifier :: OrderExecutionIdentifier
  , oeStatus :: ExecutionStatus
  , oeRequest :: ExecutionRequest
  , oeAttemptCount :: Int
  , oeRetryPolicy :: RetryPolicySnapshot
  , oeAttempts :: [ExecutionAttempt]
  , oeBrokerOrder :: Maybe BrokerOrder
  , oeReasonCode :: Maybe ReasonCode
  , oeFailureDetail :: Maybe FailureDetail
  , oeTrace :: Trace
  , oeLastAttemptAt :: Maybe UTCTime
  , oeExecutedAt :: Maybe UTCTime
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor — AcceptApprovedOrder コマンド (Must-04)
-- ---------------------------------------------------------------------

{- | Must-04: 承認済み注文を受理して執行集約を生成する。
status=APPROVED, attemptCount=0 で初期化。identifier はここで一度だけ設定され不変（§4.1 不変条件4）。
-}
acceptApprovedOrder ::
  OrderExecutionIdentifier ->
  ExecutionRequest ->
  RetryPolicySnapshot ->
  Trace ->
  OrderExecution
acceptApprovedOrder orderIdentifier request retryPolicy traceValue =
  OrderExecution
    { oeIdentifier = orderIdentifier
    , oeStatus = Approved
    , oeRequest = request
    , oeAttemptCount = 0
    , oeRetryPolicy = retryPolicy
    , oeAttempts = []
    , oeBrokerOrder = Nothing
    , oeReasonCode = Nothing
    , oeFailureDetail = Nothing
    , oeTrace = traceValue
    , oeLastAttemptAt = Nothing
    , oeExecutedAt = Nothing
    }

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

{- | Must-07 RULE-EX-005 INV-EX-001: ブローカー発注成功を記録する。
status=APPROVED のときのみ EXECUTED へ遷移し brokerOrder/executedAt を保存する。
終端状態（EXECUTED/FAILED）からは Left（再確定禁止, Must-10）。
副作用なし。(OrderExecution, [OrderExecutionEvent]) を返す。
-}
recordBrokerSuccess ::
  BrokerOrder ->
  UTCTime ->
  OrderExecution ->
  Either DomainError (OrderExecution, [OrderExecutionEvent])
recordBrokerSuccess brokerOrderValue timestamp execution
  | execution.status /= Approved =
      Left (InvalidStateTransition (statusLabel execution) "RecordBrokerSuccess")
  | otherwise =
      let nextAttempt = execution.attemptCount + 1
          attemptEntry =
            ExecutionAttempt
              { attempt = nextAttempt
              , attemptedAt = timestamp
              , result = Success
              , reasonCode = Nothing
              }
          updated =
            execution
              { oeStatus = Executed
              , oeAttemptCount = nextAttempt
              , oeAttempts = execution.attempts <> [attemptEntry]
              , oeBrokerOrder = Just brokerOrderValue
              , oeExecutedAt = Just timestamp
              , oeLastAttemptAt = Just timestamp
              }
          event =
            OrderExecutionSucceeded
              { identifier = execution.identifier
              , brokerOrder = brokerOrderValue
              , executedAt = timestamp
              , trace = execution.trace
              }
       in Right (updated, [event])

{- | Must-08 RULE-EX-003/004 INV-EX-002: ブローカー発注失敗を記録する。
status=APPROVED のときのみ受理する。再試行判定（§5.1）:

  * retryable かつ attemptCount+1 < maxAttempts → APPROVED 維持・attemptCount++・OrderExecutionAttempted。
  * retryable かつ attemptCount+1 >= maxAttempts → FAILED 確定・reasonCode 保存・OrderExecutionFailed。
  * 非 retryable → 即時 FAILED 確定・reasonCode 保存・OrderExecutionFailed。

終端状態からは Left（再確定禁止, Must-10）。副作用なし。
-}
recordBrokerFailure ::
  FailureDetail ->
  UTCTime ->
  OrderExecution ->
  Either DomainError (OrderExecution, [OrderExecutionEvent])
recordBrokerFailure failure timestamp execution
  | execution.status /= Approved =
      Left (InvalidStateTransition (statusLabel execution) "RecordBrokerFailure")
  | otherwise =
      let nextAttempt = execution.attemptCount + 1
          maxAttempts = execution.retryPolicy.maxAttempts
          canRetry = failure.retryable && nextAttempt < maxAttempts
          attemptResult = if canRetry then RetryableFailure else FinalFailure
          attemptEntry =
            ExecutionAttempt
              { attempt = nextAttempt
              , attemptedAt = timestamp
              , result = attemptResult
              , reasonCode = Just failure.reasonCode
              }
          baseUpdated =
            execution
              { oeAttemptCount = nextAttempt
              , oeAttempts = execution.attempts <> [attemptEntry]
              , oeLastAttemptAt = Just timestamp
              }
       in if canRetry
            then
              let updated = baseUpdated
                  event =
                    OrderExecutionAttempted
                      { identifier = execution.identifier
                      , attempt = nextAttempt
                      , trace = execution.trace
                      }
               in Right (updated, [event])
            else
              let updated =
                    baseUpdated
                      { oeStatus = Failed
                      , oeReasonCode = Just failure.reasonCode
                      , oeFailureDetail = Just failure
                      }
                  event =
                    OrderExecutionFailed
                      { identifier = execution.identifier
                      , reasonCode = failure.reasonCode
                      , attempt = nextAttempt
                      , trace = execution.trace
                      }
               in Right (updated, [event])

-- | TerminateExecution — 管理コマンド（純粋、イベントなし）。
terminateExecution :: OrderExecution -> OrderExecution
terminateExecution = id

-- ---------------------------------------------------------------------
-- Repository Port (Must-12)
-- ---------------------------------------------------------------------

data OrderExecutionSearchCriteria = OrderExecutionSearchCriteria
  { statusFilter :: Maybe ExecutionStatus
  , limitCount :: Maybe Int
  }
  deriving stock (Eq, Show)

emptyOrderExecutionSearchCriteria :: OrderExecutionSearchCriteria
emptyOrderExecutionSearchCriteria =
  OrderExecutionSearchCriteria
    { statusFilter = Nothing
    , limitCount = Nothing
    }

{- | Must-12: OrderExecutionRepository 型クラス Port（実装は infra 層）。
§4.5.1 命名規則: Find / FindBy{XXX} / Search / Persist / Terminate。
-}
class (Monad m) => OrderExecutionRepository m where
  find :: OrderExecutionIdentifier -> m (Maybe OrderExecution)
  findByStatus :: ExecutionStatus -> m [OrderExecution]
  search :: OrderExecutionSearchCriteria -> m [OrderExecution]
  persist :: OrderExecution -> m ()
  terminate :: OrderExecutionIdentifier -> m ()

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

statusLabel :: OrderExecution -> Text
statusLabel execution = case execution.status of
  Approved -> "approved"
  Executed -> "executed"
  Failed -> "failed"

-- ---------------------------------------------------------------------
-- Read-only field access via HasField
-- ---------------------------------------------------------------------

instance HasField "identifier" OrderExecution OrderExecutionIdentifier where
  getField OrderExecution{oeIdentifier = x} = x

instance HasField "status" OrderExecution ExecutionStatus where
  getField OrderExecution{oeStatus = x} = x

instance HasField "request" OrderExecution ExecutionRequest where
  getField OrderExecution{oeRequest = x} = x

instance HasField "attemptCount" OrderExecution Int where
  getField OrderExecution{oeAttemptCount = x} = x

instance HasField "retryPolicy" OrderExecution RetryPolicySnapshot where
  getField OrderExecution{oeRetryPolicy = x} = x

instance HasField "attempts" OrderExecution [ExecutionAttempt] where
  getField OrderExecution{oeAttempts = x} = x

instance HasField "brokerOrder" OrderExecution (Maybe BrokerOrder) where
  getField OrderExecution{oeBrokerOrder = x} = x

instance HasField "reasonCode" OrderExecution (Maybe ReasonCode) where
  getField OrderExecution{oeReasonCode = x} = x

instance HasField "failureDetail" OrderExecution (Maybe FailureDetail) where
  getField OrderExecution{oeFailureDetail = x} = x

instance HasField "trace" OrderExecution Trace where
  getField OrderExecution{oeTrace = x} = x

instance HasField "lastAttemptAt" OrderExecution (Maybe UTCTime) where
  getField OrderExecution{oeLastAttemptAt = x} = x

instance HasField "executedAt" OrderExecution (Maybe UTCTime) where
  getField OrderExecution{oeExecutedAt = x} = x
