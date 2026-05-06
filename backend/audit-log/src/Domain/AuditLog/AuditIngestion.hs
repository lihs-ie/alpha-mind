module Domain.AuditLog.AuditIngestion (
  -- * Identifier
  AuditIngestionIdentifier (..),

  -- * Value objects
  TargetEventType (..),
  DispatchDecision (..),

  -- * Aggregate (construct via 'startIngestion' only)
  AuditIngestion (..),

  -- * Smart constructor
  startIngestion,

  -- * Commands
  checkIdempotency,
  markProcessed,
  markFailed,
  decideDispatch,

  -- * Repository
  AuditIngestionRepository (..),

  -- * Domain Service — Ingestion Policy
  isDuplicate,
)
where

import Data.Maybe (isJust, isNothing)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.AuditLog (Trace)
import Domain.AuditLog.Error (DomainError (..))
import Domain.AuditLog.ReasonCode (ReasonCode)

-- ---------------------------------------------------------------------
-- Identifier
-- ---------------------------------------------------------------------

newtype AuditIngestionIdentifier = AuditIngestionIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Value Objects
-- ---------------------------------------------------------------------

data TargetEventType
  = AuditRecorded
  deriving stock (Eq, Ord, Show)

data DispatchDecision = DispatchDecision
  { shouldPublish :: Bool
  , targetEventType :: Maybe TargetEventType
  , reasonCode :: Maybe ReasonCode
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Aggregate (constructor hidden from external modules)
-- ---------------------------------------------------------------------

data AuditIngestion = AuditIngestion
  { identifier :: AuditIngestionIdentifier
  , processed :: Bool
  , processedAt :: Maybe UTCTime
  , trace :: Trace
  , reasonCode :: Maybe ReasonCode
  , dispatchDecision :: Maybe DispatchDecision
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor (StartIngestion command)
-- ---------------------------------------------------------------------

startIngestion :: AuditIngestionIdentifier -> Trace -> AuditIngestion
startIngestion ingestionIdentifier traceValue =
  AuditIngestion
    { identifier = ingestionIdentifier
    , processed = False
    , processedAt = Nothing
    , trace = traceValue
    , reasonCode = Nothing
    , dispatchDecision = Nothing
    }

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

-- | INV-AU-002: 冪等性チェック。処理済みまたは失敗済みなら AlreadyProcessed を返す。
checkIdempotency :: AuditIngestion -> Either DomainError ()
checkIdempotency ingestion
  | ingestion.processed = Left AlreadyProcessed
  | isJust ingestion.reasonCode = Left AlreadyProcessed
  | otherwise = Right ()

-- | INV-AU-002: processed 状態へ遷移。new 状態でのみ有効。
markProcessed :: UTCTime -> AuditIngestion -> Either DomainError AuditIngestion
markProcessed timestamp ingestion
  | ingestion.processed = Left AlreadyProcessed
  | isJust ingestion.reasonCode = Left (InvalidStateTransition "failed" "MarkProcessed")
  | otherwise =
      Right
        ingestion
          { processed = True
          , processedAt = Just timestamp
          }

-- | failed 状態へ遷移。new 状態でのみ有効。
markFailed :: ReasonCode -> AuditIngestion -> Either DomainError AuditIngestion
markFailed code ingestion
  | ingestion.processed = Left (InvalidStateTransition "processed" "MarkFailed")
  | isJust ingestion.reasonCode = Left (InvalidStateTransition "failed" "MarkFailed")
  | otherwise =
      Right
        AuditIngestion
          { identifier = ingestion.identifier
          , processed = ingestion.processed
          , processedAt = ingestion.processedAt
          , trace = ingestion.trace
          , reasonCode = Just code
          , dispatchDecision = ingestion.dispatchDecision
          }

-- | INV-AU-004: 発行判定を設定する。処理完了後（processed または failed）でのみ有効。
decideDispatch :: DispatchDecision -> AuditIngestion -> Either DomainError AuditIngestion
decideDispatch decision ingestion
  | not ingestion.processed && isNothing ingestion.reasonCode =
      Left (InvalidStateTransition "new" "DecideDispatch")
  | otherwise = Right ingestion{dispatchDecision = Just decision}

-- ---------------------------------------------------------------------
-- Repository
-- ---------------------------------------------------------------------

class (Monad m) => AuditIngestionRepository m where
  find :: AuditIngestionIdentifier -> m (Maybe AuditIngestion)
  persist :: AuditIngestion -> m ()
  terminate :: AuditIngestionIdentifier -> m ()

-- ---------------------------------------------------------------------
-- Domain Service — Ingestion Policy
-- ---------------------------------------------------------------------

-- | 冪等判定: 処理済みまたは失敗済みの AuditIngestion は重複とみなす。
isDuplicate :: AuditIngestion -> Bool
isDuplicate ingestion = ingestion.processed || isJust ingestion.reasonCode
