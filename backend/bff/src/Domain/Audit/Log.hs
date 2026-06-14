module Domain.Audit.Log (
  AuditResult (..),
  AuditSummary (..),
  AuditDetail (..),
  auditResultToText,
)
where

import Data.Text (Text)
import Data.Time (UTCTime)

-- | Outcome of an audited operation.
data AuditResult = AuditSuccess | AuditFailed
  deriving stock (Show, Eq)

-- | Convert 'AuditResult' to OpenAPI string value.
auditResultToText :: AuditResult -> Text
auditResultToText AuditSuccess = "success"
auditResultToText AuditFailed = "failed"

-- | Read model for audit log list items.
data AuditSummary = AuditSummary
  { identifier :: Text
  , occurredAt :: UTCTime
  , eventType :: Text
  , service :: Text
  , result :: AuditResult
  , trace :: Text
  }

-- | Extended audit log detail including payload.
data AuditDetail = AuditDetail
  { identifier :: Text
  , occurredAt :: UTCTime
  , eventType :: Text
  , service :: Text
  , result :: AuditResult
  , trace :: Text
  , reason :: Maybe Text
  }
