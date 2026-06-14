{-# LANGUAGE NoFieldSelectors #-}

-- | OrderProposal aggregate root — MUST-01, MUST-02, MUST-09, MUST-10.
module Domain.OrderProposal.Aggregate (
  -- * Identifiers
  OrderProposalIdentifier (..),

  -- * Enums
  Side (..),
  OrderStatus (..),

  -- * Aggregate (construct via 'createProposal' only; constructor intentionally hidden)
  OrderProposal,

  -- * Smart constructor
  createProposal,

  -- * Commands
  rejectProposal,
  approveProposal,
  markExecuted,
  markFailed,

  -- * Search criteria
  OrderProposalSearchCriteria (..),
  emptyOrderProposalSearchCriteria,

  -- * Domain Events
  OrderProposalEvent (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.OrderProposal (Trace)
import Domain.OrderProposal.Error (DomainError (..))
import Domain.OrderProposal.ValueObjects (
  PositionSnapshot,
  SignalSnapshot,
  StrategySnapshot,
 )
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- Identifiers (MUST-29: XXXIdentifier 形式)
-- ---------------------------------------------------------------------

newtype OrderProposalIdentifier = OrderProposalIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------

-- | MUST-02 側面: BUY | SELL の 2 値。
data Side
  = Buy
  | Sell
  deriving stock (Eq, Ord, Show)

-- | MUST-02: OrderStatus — PROPOSED | APPROVED | REJECTED | EXECUTED | FAILED の 5 値のみ。
data OrderStatus
  = Proposed
  | Approved
  | Rejected
  | Executed
  | Failed
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Domain Events (MUST-26)
-- INV-PP-006: trace フィールド必須 — 全バリアントに trace が存在する。
-- ---------------------------------------------------------------------

data OrderProposalEvent
  = OrderProposalCreated
  { identifier :: OrderProposalIdentifier
  , symbol :: Text
  , side :: Side
  , qty :: Rational
  , trace :: Trace
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Aggregate
--
-- コンストラクタは隠蔽。外部からは createProposal + コマンド関数で操作する。
-- フィールドは op プレフィックスで HasField 衝突を回避 (DuplicateRecordFields 対策)。
-- MUST-01: 全フィールドを保持。
-- ---------------------------------------------------------------------

data OrderProposal = OrderProposal
  { opIdentifier :: OrderProposalIdentifier
  , opSymbol :: Text
  , opSide :: Side
  , opQty :: Rational
  , opStatus :: OrderStatus
  , opTrace :: Trace
  , opCreatedAt :: UTCTime
  , opSignalSnapshot :: SignalSnapshot
  , opPositionSnapshot :: Maybe PositionSnapshot
  , opStrategySnapshot :: StrategySnapshot
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor — createProposal (MUST-09, MUST-10)
-- ---------------------------------------------------------------------

{- | MUST-09: 生成時の status を必ず Proposed に固定する (INV-PP-001)。
MUST-10: qty <= 0 のとき Left を返し集約を生成しない (INV-PP-002)。
-}
createProposal ::
  OrderProposalIdentifier ->
  Text ->
  Side ->
  Rational ->
  SignalSnapshot ->
  Maybe PositionSnapshot ->
  StrategySnapshot ->
  Trace ->
  UTCTime ->
  Either DomainError (OrderProposal, [OrderProposalEvent])
createProposal inputIdentifier sym inputSide inputQty signalSnap posSnap stratSnap traceValue createdTime
  | inputQty <= 0 =
      Left (InvariantViolation "OrderProposal" "qty must be positive (INV-PP-002)")
  | otherwise =
      let proposal =
            OrderProposal
              { opIdentifier = inputIdentifier
              , opSymbol = sym
              , opSide = inputSide
              , opQty = inputQty
              , opStatus = Proposed
              , opTrace = traceValue
              , opCreatedAt = createdTime
              , opSignalSnapshot = signalSnap
              , opPositionSnapshot = posSnap
              , opStrategySnapshot = stratSnap
              }
          event =
            OrderProposalCreated
              { identifier = inputIdentifier
              , symbol = sym
              , side = inputSide
              , qty = inputQty
              , trace = traceValue
              }
       in Right (proposal, [event])

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

-- | Proposed → Rejected 遷移。
rejectProposal ::
  OrderProposal ->
  Either DomainError OrderProposal
rejectProposal proposal
  | proposal.status /= Proposed =
      Left (InvalidStateTransition (orderStatusLabel proposal) "RejectProposal")
  | otherwise =
      Right proposal{opStatus = Rejected}

-- | Proposed → Approved 遷移。
approveProposal ::
  OrderProposal ->
  Either DomainError OrderProposal
approveProposal proposal
  | proposal.status /= Proposed =
      Left (InvalidStateTransition (orderStatusLabel proposal) "ApproveProposal")
  | otherwise =
      Right proposal{opStatus = Approved}

-- | Approved → Executed 遷移。
markExecuted ::
  OrderProposal ->
  Either DomainError OrderProposal
markExecuted proposal
  | proposal.status /= Approved =
      Left (InvalidStateTransition (orderStatusLabel proposal) "MarkExecuted")
  | otherwise =
      Right proposal{opStatus = Executed}

-- | Approved → Failed 遷移。
markFailed ::
  OrderProposal ->
  Either DomainError OrderProposal
markFailed proposal
  | proposal.status /= Approved =
      Left (InvalidStateTransition (orderStatusLabel proposal) "MarkFailed")
  | otherwise =
      Right proposal{opStatus = Failed}

-- ---------------------------------------------------------------------
-- Search Criteria
-- ---------------------------------------------------------------------

data OrderProposalSearchCriteria = OrderProposalSearchCriteria
  { statusFilter :: Maybe OrderStatus
  , sideFilter :: Maybe Side
  , limitCount :: Maybe Int
  }
  deriving stock (Eq, Show)

emptyOrderProposalSearchCriteria :: OrderProposalSearchCriteria
emptyOrderProposalSearchCriteria =
  OrderProposalSearchCriteria
    { statusFilter = Nothing
    , sideFilter = Nothing
    , limitCount = Nothing
    }

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

orderStatusLabel :: OrderProposal -> Text
orderStatusLabel proposal = case proposal.status of
  Proposed -> "proposed"
  Approved -> "approved"
  Rejected -> "rejected"
  Executed -> "executed"
  Failed -> "failed"

-- ---------------------------------------------------------------------
-- Read-only field access via HasField (NoFieldSelectors 回避)
-- ---------------------------------------------------------------------

instance HasField "identifier" OrderProposal OrderProposalIdentifier where
  getField OrderProposal{opIdentifier = x} = x

instance HasField "symbol" OrderProposal Text where
  getField OrderProposal{opSymbol = x} = x

instance HasField "side" OrderProposal Side where
  getField OrderProposal{opSide = x} = x

instance HasField "qty" OrderProposal Rational where
  getField OrderProposal{opQty = x} = x

instance HasField "status" OrderProposal OrderStatus where
  getField OrderProposal{opStatus = x} = x

instance HasField "trace" OrderProposal Trace where
  getField OrderProposal{opTrace = x} = x

instance HasField "createdAt" OrderProposal UTCTime where
  getField OrderProposal{opCreatedAt = x} = x

instance HasField "signalSnapshot" OrderProposal SignalSnapshot where
  getField OrderProposal{opSignalSnapshot = x} = x

instance HasField "positionSnapshot" OrderProposal (Maybe PositionSnapshot) where
  getField OrderProposal{opPositionSnapshot = x} = x

instance HasField "strategySnapshot" OrderProposal StrategySnapshot where
  getField OrderProposal{opStrategySnapshot = x} = x
