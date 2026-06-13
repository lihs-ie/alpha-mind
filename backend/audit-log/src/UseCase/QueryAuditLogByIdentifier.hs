module UseCase.QueryAuditLogByIdentifier (
  -- * Output
  AuditDetail (..),

  -- * Error
  QueryAuditLogError (..),

  -- * Use case
  queryAuditLogByIdentifier,
)
where

import Data.Aeson (Value)
import Data.Time (UTCTime)
import Domain.AuditLog (EventType, Reason, Service, Trace)
import Domain.AuditLog.AuditRecord (
  AuditRecord,
  AuditRecordIdentifier,
  AuditRecordRepository (..),
  SourceEventSnapshot (..),
 )
import Domain.AuditLog.Result (Result)

-- ---------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------

data AuditDetail = AuditDetail
  { identifier :: AuditRecordIdentifier
  , occurredAt :: UTCTime
  , eventType :: EventType
  , service :: Service
  , result :: Result
  , trace :: Trace
  , payload :: Maybe Value
  , reason :: Maybe Reason
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Error
-- ---------------------------------------------------------------------

newtype QueryAuditLogError = AuditLogNotFound AuditRecordIdentifier
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Use case
-- ---------------------------------------------------------------------

-- | UC-AU-03: 識別子を指定して監査ログ詳細を取得する。
queryAuditLogByIdentifier ::
  (AuditRecordRepository m) =>
  AuditRecordIdentifier ->
  m (Either QueryAuditLogError AuditDetail)
queryAuditLogByIdentifier recordIdentifier = do
  maybeRecord <- find recordIdentifier
  pure $ case maybeRecord of
    Nothing -> Left (AuditLogNotFound recordIdentifier)
    Just record -> Right (toAuditDetail record)

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

toAuditDetail :: AuditRecord -> AuditDetail
toAuditDetail record =
  AuditDetail
    { identifier = record.identifier
    , occurredAt = record.occurredAt
    , eventType = record.eventType
    , service = record.service
    , result = record.result
    , trace = record.trace
    , payload = let SourceEventSnapshot{payload = p} = record.sourceEventSnapshot in Just p
    , reason = record.reason
    }
