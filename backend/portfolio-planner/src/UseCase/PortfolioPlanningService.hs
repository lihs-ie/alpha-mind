{- | PortfolioPlanningService — MUST-01 through MUST-10.
Application service: orchestrates idempotency check, eligibility check,
dispatch/order creation, persistence, and result construction.
Contains NO business rules — delegates to ProposalEligibilityPolicy and OrderSizingPolicy.
-}
module UseCase.PortfolioPlanningService (
  -- * Input type
  ProposeOrdersInput (..),

  -- * Result type
  ProposeOrdersResult (..),

  -- * Use case
  proposeOrders,
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.OrderProposal (Trace)
import Domain.OrderProposal.Aggregate (
  OrderProposalIdentifier,
  Side (..),
  createProposal,
 )
import Domain.OrderProposal.Error (DomainError (..))
import Domain.OrderProposal.Factory.ProposalDispatchFactory (fromSignalGeneratedEvent)
import Domain.OrderProposal.Ports (
  IdempotencyKeyRepository (..),
  OrderProposalRepository (..),
  ProposalDispatchRepository (..),
 )
import Domain.OrderProposal.ProposalDispatch (
  ProposalDispatch,
  ProposalDispatchIdentifier,
  completeDispatch,
  failDispatch,
 )
import Domain.OrderProposal.ReasonCode (ReasonCode)
import Domain.OrderProposal.ReasonCode qualified as ReasonCode
import Domain.OrderProposal.Service.OrderSizingPolicy (calculateQuantity)
import Domain.OrderProposal.Service.ProposalEligibilityPolicy (checkEligibility)
import Domain.OrderProposal.ValueObjects (SignalSnapshot (..), StrategySnapshot (..))

-- ---------------------------------------------------------------------
-- Input type (MUST-01)
-- ---------------------------------------------------------------------

{- | ProposeOrdersInput — decoded from signal.generated event envelope.
MUST-08: trace フィールドと eventIdentifier を必ず含む。
orderProposalIdentifier は呼び出し元 (presentation 層) が ULID.getULID で生成して渡す。
これにより UseCase 層を pure (MonadIO 非依存) に保つ。
-}
data ProposeOrdersInput = ProposeOrdersInput
  { eventIdentifier :: ProposalDispatchIdentifier
  , orderProposalIdentifier :: OrderProposalIdentifier
  , signalSnapshot :: SignalSnapshot
  , strategySnapshot :: StrategySnapshot
  , proposalSymbol :: Text
  , proposalSide :: Side
  , trace :: Trace
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Result type (MUST-01)
-- ---------------------------------------------------------------------

{- | ProposeOrdersResult — tells the presentation layer what events to publish.
MUST-08: 全パスで trace フィールドと入力 eventIdentifier を含む。
RULE-PP-006: orders are persisted before this result is returned;
             presentation layer publishes events from this result.
-}
data ProposeOrdersResult
  = ProposeOrdersSucceeded
      { orders :: [OrderProposalIdentifier]
      , dispatch :: ProposalDispatchIdentifier
      , trace :: Trace
      }
  | ProposeOrdersFailed
      { reasonCode :: ReasonCode
      , dispatch :: ProposalDispatchIdentifier
      , trace :: Trace
      }
  | ProposeOrdersDuplicate
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Use case (MUST-01)
-- ---------------------------------------------------------------------

{- | proposeOrders — UC-PP-01: signal.generated イベントを受信し、
冪等性チェック → 適格性チェック → 注文候補生成・永続化 → 結果返却をオーケストレーションする。

処理順序 (§4.4 設計書準拠):
1. 冪等性チェック (MUST-03): findIdempotencyKey → 既処理なら ProposeOrdersDuplicate
2. 適格性チェック (MUST-05): checkEligibility → Left なら失敗結果
3. dispatch 生成・永続化 (Pending)
4. 注文数量計算 (MUST-02): calculateQuantity (OrderSizingPolicy)
5. 注文候補生成・永続化 (MUST-07): createProposal → persistOrderProposal
6. dispatch 完了・永続化 (MUST-09): completeDispatch → persistProposalDispatch
7. 冪等性キー記録 (MUST-04): persistIdempotencyKey
8. ProposeOrdersSucceeded を返却 (RULE-PP-006)

失敗時 (step 2 以降):
- failDispatch → persistProposalDispatch
- ProposeOrdersFailed を返却

MUST-10: インフラ固有型 (Firestore / PubSub / gogol) は import しない。
-}
proposeOrders ::
  ( OrderProposalRepository m
  , ProposalDispatchRepository m
  , IdempotencyKeyRepository m
  ) =>
  UTCTime ->
  ProposeOrdersInput ->
  m ProposeOrdersResult
proposeOrders currentTime input = do
  -- Step 1: 冪等性チェック (MUST-03, RULE-PP-003)
  existingKey <- findIdempotencyKey input.eventIdentifier
  case existingKey of
    Just _ -> pure ProposeOrdersDuplicate
    Nothing -> processNewProposal currentTime input

-- | 冪等チェック通過後の提案処理本体。
processNewProposal ::
  ( OrderProposalRepository m
  , ProposalDispatchRepository m
  , IdempotencyKeyRepository m
  ) =>
  UTCTime ->
  ProposeOrdersInput ->
  m ProposeOrdersResult
processNewProposal currentTime input = do
  -- Step 2: 適格性チェック (MUST-05, RULE-PP-001, RULE-PP-002)
  case checkEligibility input.signalSnapshot of
    Left domainError -> do
      -- 適格性失敗: dispatch は作らず直接失敗結果を返す
      let failureReasonCode = domainErrorToReasonCode domainError
      pure
        ProposeOrdersFailed
          { reasonCode = failureReasonCode
          , dispatch = input.eventIdentifier
          , trace = input.trace
          }
    Right () ->
      runDispatchFlow currentTime input

-- | 適格性チェック通過後のディスパッチ・注文生成フロー。
runDispatchFlow ::
  ( OrderProposalRepository m
  , ProposalDispatchRepository m
  , IdempotencyKeyRepository m
  ) =>
  UTCTime ->
  ProposeOrdersInput ->
  m ProposeOrdersResult
runDispatchFlow currentTime input = do
  -- Step 3: dispatch 生成・永続化 (Pending)
  let (pendingDispatch, _dispatchEvents) =
        fromSignalGeneratedEvent
          input.eventIdentifier
          input.signalSnapshot
          input.trace
  persistProposalDispatch pendingDispatch

  -- Step 4 + 5: 注文候補生成・永続化 (MUST-02, MUST-07)
  let strategySnap = input.strategySnapshot
  let rawQty = strategySnap.maxSingleOrderQty
  case calculateQuantity strategySnap rawQty of
    Left _ ->
      -- 数量計算失敗 → dispatch を失敗状態に遷移 (RULE-PP-007)
      failAndReturn
        currentTime
        input.eventIdentifier
        input.trace
        pendingDispatch
        ReasonCode.RequestValidationFailed
    Right cappedQty -> do
      case createProposal
        input.orderProposalIdentifier
        input.proposalSymbol
        input.proposalSide
        cappedQty
        input.signalSnapshot
        Nothing
        strategySnap
        input.trace
        currentTime of
        Left _ ->
          -- 注文生成失敗 → dispatch 失敗 (RULE-PP-007)
          failAndReturn
            currentTime
            input.eventIdentifier
            input.trace
            pendingDispatch
            ReasonCode.RequestValidationFailed
        Right (orderProposal, _orderEvents) -> do
          -- MUST-07: persistOrderProposal 成功後のみ結果に含める (RULE-PP-006)
          persistOrderProposal orderProposal

          let newOrders = [input.orderProposalIdentifier]
          let orderCount = length newOrders

          -- Step 6: dispatch 完了・永続化 (MUST-09)
          case completeDispatch orderCount newOrders currentTime pendingDispatch of
            Left _ ->
              -- dispatch 完了失敗 (想定外) → 失敗として返す
              failAndReturn
                currentTime
                input.eventIdentifier
                input.trace
                pendingDispatch
                ReasonCode.RequestValidationFailed
            Right (completedDispatch, _completedEvents) -> do
              persistProposalDispatch completedDispatch

              -- Step 7: 冪等性キー記録 (MUST-04)
              persistIdempotencyKey completedDispatch

              -- Step 8: 結果返却 (RULE-PP-006)
              pure
                ProposeOrdersSucceeded
                  { orders = newOrders
                  , dispatch = input.eventIdentifier
                  , trace = input.trace
                  }

-- | 失敗時のディスパッチ更新と失敗結果の返却。
failAndReturn ::
  (ProposalDispatchRepository m) =>
  UTCTime ->
  ProposalDispatchIdentifier ->
  Trace ->
  ProposalDispatch ->
  ReasonCode ->
  m ProposeOrdersResult
failAndReturn currentTime eventIdentifier traceValue pendingDispatch failureReasonCode = do
  case failDispatch (Just failureReasonCode) currentTime pendingDispatch of
    Left _ -> pure ()
    Right (failedDispatch, _) -> persistProposalDispatch failedDispatch
  pure
    ProposeOrdersFailed
      { reasonCode = failureReasonCode
      , dispatch = eventIdentifier
      , trace = traceValue
      }

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

{- | DomainError を ReasonCode にマッピングする。
RULE-PP-001: MissingRequiredFields → RequestValidationFailed
RULE-PP-002: ComplianceReviewRequired → ComplianceReviewRequired
-}
domainErrorToReasonCode :: DomainError -> ReasonCode
domainErrorToReasonCode domainError = case domainError of
  MissingRequiredFields _ -> ReasonCode.RequestValidationFailed
  ComplianceReviewRequired -> ReasonCode.ComplianceReviewRequired
  InvalidStateTransition _ _ -> ReasonCode.RequestValidationFailed
  InvariantViolation _ _ -> ReasonCode.RequestValidationFailed
  IdempotentDuplicate -> ReasonCode.IdempotencyDuplicateEvent
