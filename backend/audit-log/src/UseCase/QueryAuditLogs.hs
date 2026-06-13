module UseCase.QueryAuditLogs (
  -- * Input / Output
  AuditQueryInput (..),
  AuditSummary (..),
  AuditListResponse (..),

  -- * Use case
  queryAuditLogs,

  -- * Projection
  toAuditSummary,
)
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Domain.AuditLog (EventType, Service, Trace)
import Domain.AuditLog.AuditRecord (
  AuditRecord,
  AuditRecordIdentifier (..),
  AuditRecordRepository (..),
  SearchCriteria (..),
  emptyCriteria,
 )
import Domain.AuditLog.Result (Result)
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------
-- Input / Output
-- ---------------------------------------------------------------------

data AuditQueryInput = AuditQueryInput
  { traceFilter :: Maybe Trace
  , eventTypeFilter :: Maybe EventType
  , fromDate :: Maybe UTCTime
  , toDate :: Maybe UTCTime
  , limitCount :: Int
  , cursor :: Maybe Text
  }
  deriving stock (Eq, Show)

data AuditSummary = AuditSummary
  { identifier :: AuditRecordIdentifier
  , occurredAt :: UTCTime
  , eventType :: EventType
  , service :: Service
  , result :: Result
  , trace :: Trace
  }
  deriving stock (Eq, Show)

data AuditListResponse = AuditListResponse
  { items :: [AuditSummary]
  , nextCursor :: Maybe Text
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Use case
-- ---------------------------------------------------------------------

-- | UC-AU-02: 監査ログ一覧を検索条件で取得する。
queryAuditLogs :: (AuditRecordRepository m) => AuditQueryInput -> m AuditListResponse
queryAuditLogs input = do
  let criteria = toSearchCriteria input
      effectiveLimit = min 100 (max 1 input.limitCount)
  records <- search criteria
  let summaries = map toAuditSummary records
      nextCursor = computeNextCursor effectiveLimit summaries
  pure AuditListResponse{items = summaries, nextCursor = nextCursor}

-- ---------------------------------------------------------------------
-- Projection
-- ---------------------------------------------------------------------

toAuditSummary :: AuditRecord -> AuditSummary
toAuditSummary record =
  AuditSummary
    { identifier = record.identifier
    , occurredAt = record.occurredAt
    , eventType = record.eventType
    , service = record.service
    , result = record.result
    , trace = record.trace
    }

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

toSearchCriteria :: AuditQueryInput -> SearchCriteria
toSearchCriteria input =
  emptyCriteria
    { traceFilter = input.traceFilter
    , eventTypeFilter = input.eventTypeFilter
    , fromDate = input.fromDate
    , toDate = input.toDate
    , limitCount = Just (min 100 (max 1 input.limitCount))
    , afterIdentifier = parseCursorToIdentifier =<< input.cursor
    }

parseCursorToIdentifier :: Text -> Maybe AuditRecordIdentifier
parseCursorToIdentifier cursorText =
  case readMaybe (Text.unpack cursorText) of
    Just ulid -> Just (AuditRecordIdentifier ulid)
    Nothing -> Nothing

computeNextCursor :: Int -> [AuditSummary] -> Maybe Text
computeNextCursor limit summaries
  | length summaries >= limit =
      case lastMaybe summaries of
        Just lastItem -> Just (Text.pack (show lastItem.identifier.value))
        Nothing -> Nothing
  | otherwise = Nothing

lastMaybe :: [a] -> Maybe a
lastMaybe [] = Nothing
lastMaybe xs = Just (last xs)
