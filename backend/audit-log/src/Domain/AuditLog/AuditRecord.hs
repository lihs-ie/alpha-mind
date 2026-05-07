{-# LANGUAGE NoFieldSelectors #-}

module Domain.AuditLog.AuditRecord (
  -- * Identifiers
  AuditRecordIdentifier (..),
  SourceEventIdentifier (..),

  -- * Value objects
  PayloadSummaryValue (..),
  SourceEventSnapshot (..),
  ResultNormalization (..),
  PayloadDigest (..),

  -- * Aggregate (construct via 'acceptSourceEvent' only; constructor intentionally hidden)
  AuditRecord,

  -- * Smart constructor
  acceptSourceEvent,

  -- * Commands
  normalizeResult,
  normalizeReason,
  summarizePayload,
  markRecorded,
  markFailed,

  -- * Domain events
  AuditRecordEvent (..),

  -- * Repository
  SearchCriteria (..),
  emptyCriteria,
  AuditRecordRepository (..),

  -- * Archive
  AuditArchive (..),
  AuditArchiveRepository (..),

  -- * Domain Service — Normalization Policy
  normalizeResultFromEventType,
  extractReasonFromPayload,
)
where

import Data.Aeson (Value (..))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.AuditLog (EventType, Reason, Service, Trace)
import Domain.AuditLog.Error (DomainError (..))
import Domain.AuditLog.ReasonCode (ReasonCode)
import Domain.AuditLog.ReasonSource (ReasonSource (..))
import Domain.AuditLog.Result (Result)
import Domain.AuditLog.Result qualified as Result
import Domain.AuditLog.Status (Status)
import Domain.AuditLog.Status qualified as Status
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- Identifiers
-- ---------------------------------------------------------------------

newtype AuditRecordIdentifier = AuditRecordIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

newtype SourceEventIdentifier = SourceEventIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Value Objects
-- ---------------------------------------------------------------------

data PayloadSummaryValue
  = SummaryString Text
  | SummaryNumber Double
  | SummaryBool Bool
  deriving stock (Eq, Show)

data SourceEventSnapshot = SourceEventSnapshot
  { identifier :: SourceEventIdentifier
  , eventType :: EventType
  , occurredAt :: UTCTime
  , trace :: Trace
  , payload :: Value
  }
  deriving stock (Eq, Show)

data ResultNormalization = ResultNormalization
  { result :: Result
  , reason :: Maybe Reason
  , reasonSource :: ReasonSource
  }
  deriving stock (Eq, Show)

data PayloadDigest = PayloadDigest
  { fieldCount :: Int
  , topLevelKeys :: [Text]
  , summary :: Map Text PayloadSummaryValue
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Domain Events
-- ---------------------------------------------------------------------

data AuditRecordEvent
  = AuditRecordAccepted
      { identifier :: AuditRecordIdentifier
      , eventType :: EventType
      , trace :: Trace
      }
  | AuditRecordPersisted
      { identifier :: AuditRecordIdentifier
      , eventType :: EventType
      , service :: Service
      , result :: Result
      , trace :: Trace
      }
  | AuditRecordPersistenceFailed
      { identifier :: AuditRecordIdentifier
      , reasonCode :: ReasonCode
      , trace :: Trace
      }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Aggregate
--
-- The data constructor is intentionally hidden from the module exports.
-- Field selectors are prefixed with @ar@ to keep the auto-generated
-- HasField instances disjoint from the public field names exposed via
-- the manual HasField instances below. External callers must construct
-- AuditRecord via 'acceptSourceEvent' and mutate state via the
-- state-transition commands; read access is preserved through
-- OverloadedRecordDot.
-- ---------------------------------------------------------------------

data AuditRecord = AuditRecord
  { arIdentifier :: AuditRecordIdentifier
  , arEventType :: EventType
  , arService :: Service
  , arResult :: Result
  , arTrace :: Trace
  , arOccurredAt :: UTCTime
  , arReason :: Maybe Reason
  , arPayloadSummary :: Maybe (Map Text PayloadSummaryValue)
  , arStatus :: Status
  , arReasonCode :: Maybe ReasonCode
  , arRecordedAt :: Maybe UTCTime
  , arSourceEventSnapshot :: SourceEventSnapshot
  , arResultNormalization :: ResultNormalization
  , arPayloadDigest :: Maybe PayloadDigest
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor (AcceptSourceEvent command)
-- ---------------------------------------------------------------------

acceptSourceEvent ::
  AuditRecordIdentifier ->
  SourceEventSnapshot ->
  Service ->
  Result ->
  (AuditRecord, [AuditRecordEvent])
acceptSourceEvent recordIdentifier snapshot svc initialResult =
  let record =
        AuditRecord
          { arIdentifier = recordIdentifier
          , arEventType = snapshot.eventType
          , arService = svc
          , arResult = initialResult
          , arTrace = snapshot.trace
          , arOccurredAt = snapshot.occurredAt
          , arReason = Nothing
          , arPayloadSummary = Nothing
          , arStatus = Status.Pending
          , arReasonCode = Nothing
          , arRecordedAt = Nothing
          , arSourceEventSnapshot = snapshot
          , arResultNormalization = ResultNormalization initialResult Nothing FromNone
          , arPayloadDigest = Nothing
          }
      event =
        AuditRecordAccepted
          { identifier = recordIdentifier
          , eventType = snapshot.eventType
          , trace = snapshot.trace
          }
   in (record, [event])

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

-- | RULE-AU-003: result を正規化する。Pending 状態でのみ有効。
normalizeResult :: Result -> AuditRecord -> Either DomainError AuditRecord
normalizeResult newResult record
  | record.status /= Status.Pending = Left (InvalidStateTransition (statusLabel record) "NormalizeResult")
  | otherwise =
      Right
        record
          { arResult = newResult
          , arResultNormalization =
              ResultNormalization
                { result = newResult
                , reason = record.resultNormalization.reason
                , reasonSource = record.resultNormalization.reasonSource
                }
          }

-- | RULE-AU-004: reason を優先順位に基づき正規化する。Pending 状態でのみ有効。
normalizeReason :: Maybe Reason -> ReasonSource -> AuditRecord -> Either DomainError AuditRecord
normalizeReason newReason source record
  | record.status /= Status.Pending = Left (InvalidStateTransition (statusLabel record) "NormalizeReason")
  | otherwise =
      Right
        record
          { arReason = newReason
          , arResultNormalization =
              ResultNormalization
                { result = record.resultNormalization.result
                , reason = newReason
                , reasonSource = source
                }
          }

-- | payload を要約する。Pending 状態でのみ有効。
summarizePayload :: PayloadDigest -> AuditRecord -> Either DomainError AuditRecord
summarizePayload digest record
  | record.status /= Status.Pending = Left (InvalidStateTransition (statusLabel record) "SummarizePayload")
  | otherwise =
      Right
        record
          { arPayloadDigest = Just digest
          , arPayloadSummary = Just digest.summary
          }

-- | INV-AU-001: recorded 状態へ遷移。Pending 状態でのみ有効。
markRecorded :: UTCTime -> AuditRecord -> Either DomainError (AuditRecord, [AuditRecordEvent])
markRecorded timestamp record
  | record.status /= Status.Pending = Left (InvalidStateTransition (statusLabel record) "MarkRecorded")
  | otherwise =
      let updated =
            record
              { arStatus = Status.Recorded
              , arRecordedAt = Just timestamp
              }
          event =
            AuditRecordPersisted
              { identifier = record.identifier
              , eventType = record.eventType
              , service = record.service
              , result = record.result
              , trace = record.trace
              }
       in Right (updated, [event])

-- | INV-AU-003: failed 状態へ遷移。reasonCode を設定する。Pending 状態でのみ有効。
markFailed :: ReasonCode -> AuditRecord -> Either DomainError (AuditRecord, [AuditRecordEvent])
markFailed code record
  | record.status /= Status.Pending = Left (InvalidStateTransition (statusLabel record) "MarkFailed")
  | otherwise =
      let updated =
            record
              { arStatus = Status.Failed
              , arReasonCode = Just code
              }
          event =
            AuditRecordPersistenceFailed
              { identifier = record.identifier
              , reasonCode = code
              , trace = record.trace
              }
       in Right (updated, [event])

-- ---------------------------------------------------------------------
-- Repository
-- ---------------------------------------------------------------------

data SearchCriteria = SearchCriteria
  { eventTypeFilter :: Maybe EventType
  , serviceFilter :: Maybe Service
  , resultFilter :: Maybe Result
  , traceFilter :: Maybe Trace
  , fromDate :: Maybe UTCTime
  , toDate :: Maybe UTCTime
  , limitCount :: Maybe Int
  , afterIdentifier :: Maybe AuditRecordIdentifier
  }
  deriving stock (Eq, Show)

emptyCriteria :: SearchCriteria
emptyCriteria =
  SearchCriteria
    { eventTypeFilter = Nothing
    , serviceFilter = Nothing
    , resultFilter = Nothing
    , traceFilter = Nothing
    , fromDate = Nothing
    , toDate = Nothing
    , limitCount = Nothing
    , afterIdentifier = Nothing
    }

class (Monad m) => AuditRecordRepository m where
  find :: AuditRecordIdentifier -> m (Maybe AuditRecord)
  findByEventType :: EventType -> m [AuditRecord]
  findByTrace :: Trace -> m [AuditRecord]
  search :: SearchCriteria -> m [AuditRecord]
  persist :: AuditRecord -> m ()
  terminate :: AuditRecordIdentifier -> m ()

-- ---------------------------------------------------------------------
-- Archive
-- ---------------------------------------------------------------------

data AuditArchive = AuditArchive
  { trace :: Trace
  , identifier :: AuditRecordIdentifier
  , eventType :: EventType
  , payloadSummary :: Maybe (Map Text PayloadSummaryValue)
  }
  deriving stock (Eq, Show)

class (Monad m) => AuditArchiveRepository m where
  persistArchive :: AuditArchive -> m ()

-- ---------------------------------------------------------------------
-- Domain Service — Normalization Policy
-- ---------------------------------------------------------------------

-- | RULE-AU-003: eventType の接尾辞から result を決定する。
normalizeResultFromEventType :: EventType -> Result
normalizeResultFromEventType et
  | ".failed" `Text.isSuffixOf` et = Result.Failed
  | otherwise = Result.Success

-- | RULE-AU-004: payload から reason を優先順位で抽出する。
extractReasonFromPayload :: Value -> (Maybe Reason, ReasonSource)
extractReasonFromPayload (Object obj) =
  case ( lookupString "reasonCode" obj
       , lookupString "actionReasonCode" obj
       , lookupString "reason" obj
       ) of
    (Just rc, _, _) -> (Just rc, FromReasonCode)
    (_, Just arc, _) -> (Just arc, FromActionReasonCode)
    (_, _, Just r) -> (Just r, FromReason)
    _ -> (Nothing, FromNone)
extractReasonFromPayload _ = (Nothing, FromNone)

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

statusLabel :: AuditRecord -> Text
statusLabel record = case record.status of
  Status.Pending -> "pending"
  Status.Recorded -> "recorded"
  Status.Failed -> "failed"

lookupString :: Text -> KeyMap.KeyMap Value -> Maybe Text
lookupString key obj = case KeyMap.lookup (Key.fromText key) obj of
  Just (String s) -> Just s
  _ -> Nothing

-- ---------------------------------------------------------------------
-- Read-only field access via HasField
--
-- The data constructor is hidden from external modules to enforce that
-- AuditRecord values are only built via 'acceptSourceEvent' and mutated
-- via the state-transition commands. The HasField instances below
-- preserve OverloadedRecordDot read access (record.field) without
-- exposing record-update or constructor application.
-- ---------------------------------------------------------------------

instance HasField "identifier" AuditRecord AuditRecordIdentifier where
  getField AuditRecord{arIdentifier = x} = x

instance HasField "eventType" AuditRecord EventType where
  getField AuditRecord{arEventType = x} = x

instance HasField "service" AuditRecord Service where
  getField AuditRecord{arService = x} = x

instance HasField "result" AuditRecord Result where
  getField AuditRecord{arResult = x} = x

instance HasField "trace" AuditRecord Trace where
  getField AuditRecord{arTrace = x} = x

instance HasField "occurredAt" AuditRecord UTCTime where
  getField AuditRecord{arOccurredAt = x} = x

instance HasField "reason" AuditRecord (Maybe Reason) where
  getField AuditRecord{arReason = x} = x

instance HasField "payloadSummary" AuditRecord (Maybe (Map Text PayloadSummaryValue)) where
  getField AuditRecord{arPayloadSummary = x} = x

instance HasField "status" AuditRecord Status where
  getField AuditRecord{arStatus = x} = x

instance HasField "reasonCode" AuditRecord (Maybe ReasonCode) where
  getField AuditRecord{arReasonCode = x} = x

instance HasField "recordedAt" AuditRecord (Maybe UTCTime) where
  getField AuditRecord{arRecordedAt = x} = x

instance HasField "sourceEventSnapshot" AuditRecord SourceEventSnapshot where
  getField AuditRecord{arSourceEventSnapshot = x} = x

instance HasField "resultNormalization" AuditRecord ResultNormalization where
  getField AuditRecord{arResultNormalization = x} = x

instance HasField "payloadDigest" AuditRecord (Maybe PayloadDigest) where
  getField AuditRecord{arPayloadDigest = x} = x
