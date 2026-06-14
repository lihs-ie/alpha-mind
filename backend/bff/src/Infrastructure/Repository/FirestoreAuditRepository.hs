module Infrastructure.Repository.FirestoreAuditRepository (
  FirestoreAuditRepositoryEnv (..),
  AuditQueryFilter (..),
  listAuditLogs,
  getAuditLogByIdentifier,
)
where

import Data.Text (Text)
import Domain.Audit.Log (
  AuditDetail (..),
  AuditResult (..),
  AuditSummary (..),
 )
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext (..),
  FirestoreError,
  FromFirestore (..),
  QueryOrder (..),
  SortDirection (..),
  requireField,
 )
import Persistence.Firestore qualified as Firestore

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

-- | Environment for reading the @audit_logs@ Firestore collection.
newtype FirestoreAuditRepositoryEnv = FirestoreAuditRepositoryEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Query filter
-- ---------------------------------------------------------------------------

-- | Optional filters for the audit log list query.
data AuditQueryFilter = AuditQueryFilter
  { traceFilter :: Maybe Text
  -- ^ Filter by trace ULID.
  , eventTypeFilter :: Maybe Text
  -- ^ Filter by event type string.
  , limitCount :: Int
  -- ^ Maximum number of results.
  }

-- ---------------------------------------------------------------------------
-- FromFirestore instances
-- ---------------------------------------------------------------------------

instance FromFirestore AuditSummary where
  fromFirestoreFields fieldMap = do
    identifierValue <- requireField "identifier" fieldMap
    occurredAtValue <- requireField "occurredAt" fieldMap
    eventTypeValue <- requireField "eventType" fieldMap
    serviceValue <- requireField "service" fieldMap
    resultText <- requireField "result" fieldMap
    resultValue <- parseAuditResult resultText
    traceValue <- requireField "trace" fieldMap
    pure
      AuditSummary
        { identifier = identifierValue
        , occurredAt = occurredAtValue
        , eventType = eventTypeValue
        , service = serviceValue
        , result = resultValue
        , trace = traceValue
        }

instance FromFirestore AuditDetail where
  fromFirestoreFields fieldMap = do
    identifierValue <- requireField "identifier" fieldMap
    occurredAtValue <- requireField "occurredAt" fieldMap
    eventTypeValue <- requireField "eventType" fieldMap
    serviceValue <- requireField "service" fieldMap
    resultText <- requireField "result" fieldMap
    resultValue <- parseAuditResult resultText
    traceValue <- requireField "trace" fieldMap
    maybeReason <- requireField "reason" fieldMap
    pure
      AuditDetail
        { identifier = identifierValue
        , occurredAt = occurredAtValue
        , eventType = eventTypeValue
        , service = serviceValue
        , result = resultValue
        , trace = traceValue
        , reason = maybeReason
        }

-- ---------------------------------------------------------------------------
-- Repository operations
-- ---------------------------------------------------------------------------

{- | List audit logs ordered by @occurredAt DESC@.

Trace and eventType filters are applied when present.
-}
listAuditLogs ::
  FirestoreAuditRepositoryEnv ->
  AuditQueryFilter ->
  IO (Either FirestoreError [AuditSummary])
listAuditLogs auditRepositoryEnv queryFilter = do
  let orders = [QueryOrder{orderField = "occurredAt", orderDirection = Descending}]
      limitValue = max 1 (min 200 queryFilter.limitCount)
  Firestore.runQuery
    auditRepositoryEnv.firestoreContext
    (CollectionName "audit_logs")
    []
    orders
    limitValue
    Nothing

{- | Get a single audit log entry by its identifier.

Returns 'Nothing' if the document does not exist.
-}
getAuditLogByIdentifier ::
  FirestoreAuditRepositoryEnv ->
  Text ->
  IO (Either FirestoreError (Maybe AuditDetail))
getAuditLogByIdentifier auditRepositoryEnv auditIdentifier =
  Firestore.getDocument
    auditRepositoryEnv.firestoreContext
    (CollectionName "audit_logs")
    (DocumentId auditIdentifier)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

parseAuditResult :: Text -> Either Text AuditResult
parseAuditResult "success" = Right AuditSuccess
parseAuditResult "failed" = Right AuditFailed
parseAuditResult unknown = Left ("Unknown audit result: " <> unknown)
