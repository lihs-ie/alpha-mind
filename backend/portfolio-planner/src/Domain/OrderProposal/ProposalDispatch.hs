{-# LANGUAGE NoFieldSelectors #-}

-- | ProposalDispatch aggregate root — MUST-03, MUST-08, MUST-11, MUST-12.
module Domain.OrderProposal.ProposalDispatch (
  -- * Identifiers
  ProposalDispatchIdentifier (..),

  -- * Enums
  DispatchStatus (..),

  -- * Value Objects
  DispatchDecision (..),

  -- * Aggregate (construct via 'startDispatch' only; constructor intentionally hidden)
  ProposalDispatch,

  -- * Smart constructor
  startDispatch,

  -- * Commands
  completeDispatch,
  failDispatch,
  terminateDispatch,

  -- * Domain Events
  ProposalDispatchEvent (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.OrderProposal (Trace)
import Domain.OrderProposal.Aggregate (OrderProposalIdentifier)
import Domain.OrderProposal.Error (DomainError (..))
import Domain.OrderProposal.ReasonCode (ReasonCode)
import Domain.OrderProposal.ValueObjects (AccountSnapshot, SignalSnapshot)
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- Identifiers (MUST-29)
-- ---------------------------------------------------------------------

newtype ProposalDispatchIdentifier = ProposalDispatchIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------

-- | DispatchStatus — Pending | Completed | Failed の 3 値。
data DispatchStatus
  = Pending
  | Completed
  | Failed
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Value Objects (MUST-08)
-- ---------------------------------------------------------------------

-- | DispatchDecision — ディスパッチ判定結果。immutable。
data DispatchDecision = DispatchDecision
  { dispatchStatus :: DispatchStatus
  , reasonCode :: Maybe ReasonCode
  , detail :: Maybe Text
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Domain Events (MUST-27, MUST-28)
-- INV-PP-006: trace フィールド必須 — 全バリアントに trace が存在する。
-- ---------------------------------------------------------------------

data ProposalDispatchEvent
  = ProposalDispatchCompleted
      { identifier :: ProposalDispatchIdentifier
      , orderCount :: Int
      , orders :: [OrderProposalIdentifier]
      , trace :: Trace
      }
  | ProposalDispatchFailed
      { identifier :: ProposalDispatchIdentifier
      , reasonCode :: ReasonCode
      , trace :: Trace
      }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Aggregate
--
-- コンストラクタは隠蔽。フィールドは pd プレフィックスで HasField 衝突を回避。
-- MUST-03: 全フィールドを保持。
-- ---------------------------------------------------------------------

data ProposalDispatch = ProposalDispatch
  { pdIdentifier :: ProposalDispatchIdentifier
  , pdDispatchStatus :: DispatchStatus
  , pdOrderCount :: Maybe Int
  , pdOrders :: [OrderProposalIdentifier]
  , pdReasonCode :: Maybe ReasonCode
  , pdTrace :: Trace
  , pdProcessedAt :: Maybe UTCTime
  , pdSignalSnapshot :: SignalSnapshot
  , pdAccountSnapshot :: Maybe AccountSnapshot
  , pdDispatchDecision :: DispatchDecision
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor — startDispatch (MUST-25)
-- ---------------------------------------------------------------------

{- | MUST-25: 入力イベントの identifier を ProposalDispatch.identifier に設定し、
初期 dispatchStatus を Pending にする。
-}
startDispatch ::
  ProposalDispatchIdentifier ->
  SignalSnapshot ->
  Trace ->
  (ProposalDispatch, [ProposalDispatchEvent])
startDispatch inputIdentifier signalSnap traceValue =
  let dispatch =
        ProposalDispatch
          { pdIdentifier = inputIdentifier
          , pdDispatchStatus = Pending
          , pdOrderCount = Nothing
          , pdOrders = []
          , pdReasonCode = Nothing
          , pdTrace = traceValue
          , pdProcessedAt = Nothing
          , pdSignalSnapshot = signalSnap
          , pdAccountSnapshot = Nothing
          , pdDispatchDecision =
              DispatchDecision
                { dispatchStatus = Pending
                , reasonCode = Nothing
                , detail = Nothing
                }
          }
   in (dispatch, [])

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

-- | MUST-11: CompleteDispatch — length orders /= orderCount のときエラー (INV-PP-004)。
completeDispatch ::
  Int ->
  [OrderProposalIdentifier] ->
  UTCTime ->
  ProposalDispatch ->
  Either DomainError (ProposalDispatch, [ProposalDispatchEvent])
completeDispatch count orderList timestamp dispatch
  | dispatch.dispatchStatus /= Pending =
      Left (InvalidStateTransition (dispatchStatusLabel dispatch) "CompleteDispatch")
  | count /= length orderList =
      Left (InvariantViolation "ProposalDispatch" "orderCount must equal length of orders (INV-PP-004)")
  | otherwise =
      let decision =
            DispatchDecision
              { dispatchStatus = Completed
              , reasonCode = Nothing
              , detail = Nothing
              }
          updated =
            dispatch
              { pdDispatchStatus = Completed
              , pdOrderCount = Just count
              , pdOrders = orderList
              , pdProcessedAt = Just timestamp
              , pdDispatchDecision = decision
              }
          event =
            ProposalDispatchCompleted
              { identifier = dispatch.identifier
              , orderCount = count
              , orders = orderList
              , trace = dispatch.trace
              }
       in Right (updated, [event])

-- | MUST-12: FailDispatch — reasonCode が Nothing のときエラー (INV-PP-005)。
failDispatch ::
  Maybe ReasonCode ->
  UTCTime ->
  ProposalDispatch ->
  Either DomainError (ProposalDispatch, [ProposalDispatchEvent])
failDispatch Nothing _ _ =
  Left (InvariantViolation "ProposalDispatch" "reasonCode is required for FailDispatch (INV-PP-005)")
failDispatch (Just code) timestamp dispatch
  | dispatch.dispatchStatus /= Pending =
      Left (InvalidStateTransition (dispatchStatusLabel dispatch) "FailDispatch")
  | otherwise =
      let decision =
            DispatchDecision
              { dispatchStatus = Failed
              , reasonCode = Just code
              , detail = Nothing
              }
          updated =
            dispatch
              { pdDispatchStatus = Failed
              , pdReasonCode = Just code
              , pdProcessedAt = Just timestamp
              , pdDispatchDecision = decision
              }
          event =
            ProposalDispatchFailed
              { identifier = dispatch.identifier
              , reasonCode = code
              , trace = dispatch.trace
              }
       in Right (updated, [event])

-- | TerminateDispatch — 管理コマンド（純粋）。
terminateDispatch :: ProposalDispatch -> ProposalDispatch
terminateDispatch = id

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

dispatchStatusLabel :: ProposalDispatch -> Text
dispatchStatusLabel dispatch = case dispatch.dispatchStatus of
  Pending -> "pending"
  Completed -> "completed"
  Failed -> "failed"

-- ---------------------------------------------------------------------
-- Read-only field access via HasField (NoFieldSelectors 回避)
-- ---------------------------------------------------------------------

instance HasField "identifier" ProposalDispatch ProposalDispatchIdentifier where
  getField ProposalDispatch{pdIdentifier = x} = x

instance HasField "dispatchStatus" ProposalDispatch DispatchStatus where
  getField ProposalDispatch{pdDispatchStatus = x} = x

instance HasField "orderCount" ProposalDispatch (Maybe Int) where
  getField ProposalDispatch{pdOrderCount = x} = x

instance HasField "orders" ProposalDispatch [OrderProposalIdentifier] where
  getField ProposalDispatch{pdOrders = x} = x

instance HasField "reasonCode" ProposalDispatch (Maybe ReasonCode) where
  getField ProposalDispatch{pdReasonCode = x} = x

instance HasField "trace" ProposalDispatch Trace where
  getField ProposalDispatch{pdTrace = x} = x

instance HasField "processedAt" ProposalDispatch (Maybe UTCTime) where
  getField ProposalDispatch{pdProcessedAt = x} = x

instance HasField "signalSnapshot" ProposalDispatch SignalSnapshot where
  getField ProposalDispatch{pdSignalSnapshot = x} = x

instance HasField "accountSnapshot" ProposalDispatch (Maybe AccountSnapshot) where
  getField ProposalDispatch{pdAccountSnapshot = x} = x

instance HasField "dispatchDecision" ProposalDispatch DispatchDecision where
  getField ProposalDispatch{pdDispatchDecision = x} = x
