module Domain.AuditLog.Specification (
  -- * Source Event Envelope Specification (RULE-AU-001)
  RawSourceEvent (..),
  validateSourceEventEnvelope,

  -- * Publication Eligibility Specification (RULE-AU-005)
  isEligibleForPublication,
)
where

import Data.Aeson (Value)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.AuditLog (EventType, Trace (..))
import Domain.AuditLog.AuditRecord (
  AuditRecord,
  SourceEventIdentifier (..),
  SourceEventSnapshot (..),
 )
import Domain.AuditLog.Error (DomainError (..))
import Domain.AuditLog.Status qualified as Status

-- ---------------------------------------------------------------------
-- Source Event Envelope Specification (RULE-AU-001)
-- ---------------------------------------------------------------------

data RawSourceEvent = RawSourceEvent
  { identifier :: Maybe ULID
  , eventType :: Maybe EventType
  , occurredAt :: Maybe UTCTime
  , trace :: Maybe ULID
  , payload :: Maybe Value
  }
  deriving stock (Eq, Show)

-- | RULE-AU-001: 必須属性の完全性を検証し、有効な SourceEventSnapshot を返す。
validateSourceEventEnvelope :: RawSourceEvent -> Either DomainError SourceEventSnapshot
validateSourceEventEnvelope raw =
  case (raw.identifier, raw.eventType, raw.occurredAt, raw.trace, raw.payload) of
    (Just i, Just et, Just oa, Just tr, Just pl) ->
      Right
        SourceEventSnapshot
          { identifier = SourceEventIdentifier i
          , eventType = et
          , occurredAt = oa
          , trace = Trace tr
          , payload = pl
          }
    _ -> Left (MissingRequiredFields (collectMissing raw))

collectMissing :: RawSourceEvent -> [Text]
collectMissing raw =
  concat
    [ ["identifier" | Nothing <- [raw.identifier]]
    , ["eventType" | Nothing <- [raw.eventType]]
    , ["occurredAt" | Nothing <- [raw.occurredAt]]
    , ["trace" | Nothing <- [raw.trace]]
    , ["payload" | Nothing <- [raw.payload]]
    ]

-- ---------------------------------------------------------------------
-- Publication Eligibility Specification (RULE-AU-005)
-- ---------------------------------------------------------------------

-- | RULE-AU-005: 保存成功（Recorded）の AuditRecord のみ発行可能。
isEligibleForPublication :: AuditRecord -> Bool
isEligibleForPublication record = record.status == Status.Recorded
