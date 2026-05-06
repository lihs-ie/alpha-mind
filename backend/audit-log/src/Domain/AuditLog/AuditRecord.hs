module Domain.AuditLog.AuditRecord (
  -- * Identifiers
  AuditRecordIdentifier (..),
  SourceEventIdentifier (..),

  -- * Value objects
  PayloadSummaryValue (..),
  SourceEventSnapshot (..),
  ResultNormalization (..),
  PayloadDigest (..),

  -- * Aggregate (construct via 'acceptSourceEvent' only)
  AuditRecord (..),

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
-- Aggregate (constructor hidden from external modules)
-- ---------------------------------------------------------------------

data AuditRecord = AuditRecord
  { identifier :: AuditRecordIdentifier
  , eventType :: EventType
  , service :: Service
  , result :: Result
  , trace :: Trace
  , occurredAt :: UTCTime
  , reason :: Maybe Reason
  , payloadSummary :: Maybe (Map Text PayloadSummaryValue)
  , status :: Status
  , reasonCode :: Maybe ReasonCode
  , recordedAt :: Maybe UTCTime
  , sourceEventSnapshot :: SourceEventSnapshot
  , resultNormalization :: ResultNormalization
  , payloadDigest :: Maybe PayloadDigest
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
          { identifier = recordIdentifier
          , eventType = snapshot.eventType
          , service = svc
          , result = initialResult
          , trace = snapshot.trace
          , occurredAt = snapshot.occurredAt
          , reason = Nothing
          , payloadSummary = Nothing
          , status = Status.Pending
          , reasonCode = Nothing
          , recordedAt = Nothing
          , sourceEventSnapshot = snapshot
          , resultNormalization = ResultNormalization initialResult Nothing FromNone
          , payloadDigest = Nothing
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
          { result = newResult
          , resultNormalization =
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
          { reason = newReason
          , resultNormalization =
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
          { payloadDigest = Just digest
          , payloadSummary = Just digest.summary
          }

-- | INV-AU-001: recorded 状態へ遷移。Pending 状態でのみ有効。
markRecorded :: UTCTime -> AuditRecord -> Either DomainError (AuditRecord, [AuditRecordEvent])
markRecorded timestamp record
  | record.status /= Status.Pending = Left (InvalidStateTransition (statusLabel record) "MarkRecorded")
  | otherwise =
      let updated =
            record
              { status = Status.Recorded
              , recordedAt = Just timestamp
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
              { status = Status.Failed
              , reasonCode = Just code
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
