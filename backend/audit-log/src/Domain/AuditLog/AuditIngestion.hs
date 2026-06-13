{-# LANGUAGE NoFieldSelectors #-}

module Domain.AuditLog.AuditIngestion (
  -- * Identifier
  AuditIngestionIdentifier (..),

  -- * Value objects
  TargetEventType (..),
  DispatchDecision (..),

  -- * Aggregate (construct via 'startIngestion' only; constructor intentionally hidden)
  AuditIngestion,

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
import GHC.Records (HasField (..))

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
-- Aggregate
--
-- The data constructor is intentionally hidden from the module exports.
-- Field selectors are prefixed with @ai@ so the auto-generated HasField
-- instances do not collide with the public field names exposed via the
-- manual HasField instances below. External callers must construct
-- AuditIngestion via 'startIngestion' and mutate state via the
-- state-transition commands; read access is preserved through
-- OverloadedRecordDot.
-- ---------------------------------------------------------------------

data AuditIngestion = AuditIngestion
  { aiIdentifier :: AuditIngestionIdentifier
  , aiProcessed :: Bool
  , aiProcessedAt :: Maybe UTCTime
  , aiTrace :: Trace
  , aiReasonCode :: Maybe ReasonCode
  , aiDispatchDecision :: Maybe DispatchDecision
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor (StartIngestion command)
-- ---------------------------------------------------------------------

startIngestion :: AuditIngestionIdentifier -> Trace -> AuditIngestion
startIngestion ingestionIdentifier traceValue =
  AuditIngestion
    { aiIdentifier = ingestionIdentifier
    , aiProcessed = False
    , aiProcessedAt = Nothing
    , aiTrace = traceValue
    , aiReasonCode = Nothing
    , aiDispatchDecision = Nothing
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
          { aiProcessed = True
          , aiProcessedAt = Just timestamp
          }

-- | failed 状態へ遷移。new 状態でのみ有効。
markFailed :: ReasonCode -> AuditIngestion -> Either DomainError AuditIngestion
markFailed code ingestion
  | ingestion.processed = Left (InvalidStateTransition "processed" "MarkFailed")
  | isJust ingestion.reasonCode = Left (InvalidStateTransition "failed" "MarkFailed")
  | otherwise =
      Right ingestion{aiReasonCode = Just code}

-- | INV-AU-004: 発行判定を設定する。処理完了後（processed または failed）でのみ有効。
decideDispatch :: DispatchDecision -> AuditIngestion -> Either DomainError AuditIngestion
decideDispatch decision ingestion
  | not ingestion.processed && isNothing ingestion.reasonCode =
      Left (InvalidStateTransition "new" "DecideDispatch")
  | otherwise = Right ingestion{aiDispatchDecision = Just decision}

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

-- ---------------------------------------------------------------------
-- Read-only field access via HasField
--
-- The data constructor is hidden from external modules to enforce that
-- AuditIngestion values are only built via 'startIngestion' and mutated
-- via the state-transition commands. The HasField instances below
-- preserve OverloadedRecordDot read access (ingestion.field) without
-- exposing record-update or constructor application.
-- ---------------------------------------------------------------------

instance HasField "identifier" AuditIngestion AuditIngestionIdentifier where
  getField AuditIngestion{aiIdentifier = x} = x

instance HasField "processed" AuditIngestion Bool where
  getField AuditIngestion{aiProcessed = x} = x

instance HasField "processedAt" AuditIngestion (Maybe UTCTime) where
  getField AuditIngestion{aiProcessedAt = x} = x

instance HasField "trace" AuditIngestion Trace where
  getField AuditIngestion{aiTrace = x} = x

instance HasField "reasonCode" AuditIngestion (Maybe ReasonCode) where
  getField AuditIngestion{aiReasonCode = x} = x

instance HasField "dispatchDecision" AuditIngestion (Maybe DispatchDecision) where
  getField AuditIngestion{aiDispatchDecision = x} = x
