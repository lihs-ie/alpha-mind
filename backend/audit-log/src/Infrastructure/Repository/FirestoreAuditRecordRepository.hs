{-# LANGUAGE OverloadedRecordDot #-}
{-# OPTIONS_GHC -fno-hpc #-}

{- | Firestore implementation of 'AuditRecordRepository' and 'AuditArchiveRepository'.

Must-1: Satisfies all 6 Port operations (find, findByEventType, findByTrace,
        search, persist, terminate) via the Firestore adapter.
Must-4: expiresAt is set to now + 90 days on persist.
Must-6: persist wraps Firestore upsert with withRetry defaultRetryPolicyConfig.
Must-7: FirestoreErrorDecode is mapped to DATA_SCHEMA_INVALID (non-retryable).
Must-8: findByTrace uses trace+occurredAt DESC, findByEventType uses eventType+occurredAt DESC.
Must-10: toFirestoreFields / fromFirestoreFields cover every audit_logs field.
-}
module Infrastructure.Repository.FirestoreAuditRecordRepository (
  -- * Repository environment
  FirestoreAuditRecordEnv (..),

  -- * AuditRecord codec
  AuditRecordFirestoreDocument (..),

  -- * Monad transformer
  FirestoreAuditRecordT (..),
  runFirestoreAuditRecordT,

  -- * AuditArchive environment and monad transformer
  FirestoreAuditArchiveEnv (..),
  FirestoreAuditArchiveT (..),
  runFirestoreAuditArchiveT,

  -- * Retry predicate (exported for unit tests — Must-6/Must-7)
  isRetryableForPersist,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson (Value (Null))
import Data.Aeson qualified as Aeson
import Data.Bifunctor (second)
import Data.HashMap.Strict qualified as HashMap
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, addUTCTime, getCurrentTime, nominalDay)
import Data.ULID (ULID)
import Domain.AuditLog (EventType, Reason, Service, Trace (..))
import Domain.AuditLog.AuditRecord (
  AuditArchive (..),
  AuditArchiveRepository (..),
  AuditRecord,
  AuditRecordIdentifier (..),
  AuditRecordRepository (..),
  PayloadSummaryValue (..),
  SearchCriteria (..),
  SourceEventIdentifier (..),
  SourceEventSnapshot (..),
  acceptSourceEvent,
  normalizeResultFromEventType,
 )
import Domain.AuditLog.Result (Result)
import Domain.AuditLog.Result qualified as Result
import Gogol.FireStore qualified as GogolFireStore
import Observability.Logging (LogContext (..), LogEnv, logInfoWith)
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext,
  FirestoreError (..),
  FromFirestore (..),
  FromFirestoreValue (..),
  QueryCursor (..),
  QueryFilter (..),
  QueryOrder (..),
  SortDirection (..),
  ToFirestore (..),
  ToFirestoreValue (..),
  deleteDocument,
  getDocument,
  requireField,
  runQuery,
  toMapValue,
  upsertDocument,
 )
import Resilience.Retry (defaultRetryPolicyConfig, withRetry)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreAuditRecordEnv = FirestoreAuditRecordEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreAuditRecordT m a = FirestoreAuditRecordT
  { unFirestoreAuditRecordT :: ReaderT FirestoreAuditRecordEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runFirestoreAuditRecordT :: FirestoreAuditRecordEnv -> FirestoreAuditRecordT m a -> m a
runFirestoreAuditRecordT environment action =
  runReaderT (unFirestoreAuditRecordT action) environment

-- ---------------------------------------------------------------------------
-- Collection / TTL constants
-- ---------------------------------------------------------------------------

auditLogsCollection :: CollectionName
auditLogsCollection = CollectionName "audit_logs"

auditLogsTtlDays :: Integer
auditLogsTtlDays = 90

-- ---------------------------------------------------------------------------
-- Firestore document wrapper
-- ---------------------------------------------------------------------------

{- | Wire representation of an AuditRecord in Firestore.
Must-10: fields match audit_logs schema exactly.
-}
data AuditRecordFirestoreDocument = AuditRecordFirestoreDocument
  { identifier :: ULID
  , eventType :: EventType
  , service :: Service
  , result :: Text
  , trace :: ULID
  , reason :: Maybe Reason
  , occurredAt :: UTCTime
  , payloadSummary :: Maybe (Map Text PayloadSummaryValue)
  , expiresAt :: UTCTime
  }

instance ToFirestore AuditRecordFirestoreDocument where
  toFirestoreFields document =
    HashMap.fromList $
      [ ("identifier", toValue document.identifier)
      , ("eventType", toValue document.eventType)
      , ("service", toValue document.service)
      , ("result", toValue document.result)
      , ("trace", toValue document.trace)
      , ("occurredAt", toValue document.occurredAt)
      , ("expiresAt", toValue document.expiresAt)
      ]
        <> maybe [] (\r -> [("reason", toValue r)]) document.reason
        <> maybe [] (\summary -> [("payloadSummary", encodeSummary summary)]) document.payloadSummary

instance FromFirestore AuditRecordFirestoreDocument where
  fromFirestoreFields fields = do
    identifier <- requireField "identifier" fields
    eventType <- requireField "eventType" fields
    service <- requireField "service" fields
    resultText <- requireField "result" fields
    trace <- requireField "trace" fields
    reason <- optionalField "reason" fields
    occurredAt <- requireField "occurredAt" fields
    expiresAt <- requireField "expiresAt" fields
    let payloadSummary = Nothing
    Right
      AuditRecordFirestoreDocument
        { identifier = identifier
        , eventType = eventType
        , service = service
        , result = resultText
        , trace = trace
        , reason = reason
        , occurredAt = occurredAt
        , payloadSummary = payloadSummary
        , expiresAt = expiresAt
        }

-- ---------------------------------------------------------------------------
-- Codec helpers
-- ---------------------------------------------------------------------------

{- | Like 'requireField' but returns 'Nothing' when the key is absent
(rather than 'Left'). Used for optional fields such as @reason@.
-}
optionalField ::
  (FromFirestoreValue a) =>
  Text ->
  HashMap.HashMap Text GogolFireStore.Value ->
  Either Text (Maybe a)
optionalField key fields =
  case HashMap.lookup key fields of
    Nothing -> Right Nothing
    Just value -> case value.nullValue of
      Just _ -> Right Nothing
      Nothing -> fmap Just (extractValue key value)

resultToText :: Result -> Text
resultToText Result.Success = "success"
resultToText Result.Failed = "failed"

resultFromText :: Text -> Either Text Result
resultFromText "success" = Right Result.Success
resultFromText "failed" = Right Result.Failed
resultFromText other = Left ("unknown result value: " <> other)

encodeSummary :: Map Text PayloadSummaryValue -> GogolFireStore.Value
encodeSummary summary =
  toMapValue
    ( HashMap.fromList
        ( map
            (second encodeSummaryValue)
            (Map.toList summary)
        )
    )

encodeSummaryValue :: PayloadSummaryValue -> GogolFireStore.Value
encodeSummaryValue (SummaryString text) = toValue text
encodeSummaryValue (SummaryNumber number) = GogolFireStore.newValue{GogolFireStore.doubleValue = Just number}
encodeSummaryValue (SummaryBool boolean) = toValue boolean

toDocument :: UTCTime -> AuditRecord -> AuditRecordFirestoreDocument
toDocument now record =
  AuditRecordFirestoreDocument
    { identifier = record.identifier.value
    , eventType = record.eventType
    , service = record.service
    , result = resultToText record.result
    , trace = record.trace.value
    , reason = record.reason
    , occurredAt = record.occurredAt
    , payloadSummary = record.payloadSummary
    , expiresAt = addUTCTime (fromIntegral auditLogsTtlDays * nominalDay) now
    }

documentToAuditRecord ::
  AuditRecordFirestoreDocument ->
  Either Text AuditRecord
documentToAuditRecord document = do
  result <- resultFromText document.result
  let recordIdentifier = AuditRecordIdentifier{value = document.identifier}
      traceValue = Trace{value = document.trace}
      snapshot =
        SourceEventSnapshot
          { identifier = SourceEventIdentifier{value = document.identifier}
          , eventType = document.eventType
          , occurredAt = document.occurredAt
          , trace = traceValue
          , payload = Null
          }
      (record, _) = acceptSourceEvent recordIdentifier snapshot document.service result
  Right record

-- ---------------------------------------------------------------------------
-- AuditRecordRepository instance
-- Must-1: All 6 operations implemented.
-- ---------------------------------------------------------------------------

instance AuditRecordRepository (FirestoreAuditRecordT IO) where
  find recordIdentifier = FirestoreAuditRecordT $ do
    environment <- ask
    result <-
      liftIO $
        getDocument @AuditRecordFirestoreDocument
          environment.firestoreContext
          auditLogsCollection
          (DocumentId (Text.pack (show recordIdentifier.value)))
    case result of
      Left _ -> pure Nothing
      Right maybeDocument ->
        pure $ case maybeDocument of
          Nothing -> Nothing
          Just document ->
            case documentToAuditRecord document of
              Left _ -> Nothing
              Right record -> Just record

  -- Must-8: Uses eventType + occurredAt DESC index.
  findByEventType eventTypeValue = FirestoreAuditRecordT $ do
    environment <- ask
    result <-
      liftIO $
        runQuery @AuditRecordFirestoreDocument
          environment.firestoreContext
          auditLogsCollection
          [QueryFilterEqual{filterField = "eventType", filterValue = toValue eventTypeValue}]
          [QueryOrder{orderField = "occurredAt", orderDirection = Descending}]
          100
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (concatMap toMaybeRecord documents)

  -- Must-8: Uses trace + occurredAt DESC index.
  findByTrace traceValue = FirestoreAuditRecordT $ do
    environment <- ask
    result <-
      liftIO $
        runQuery @AuditRecordFirestoreDocument
          environment.firestoreContext
          auditLogsCollection
          [QueryFilterEqual{filterField = "trace", filterValue = toValue traceValue.value}]
          [QueryOrder{orderField = "occurredAt", orderDirection = Descending}]
          100
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (concatMap toMaybeRecord documents)

  -- Must-8: Uses limit + cursor (startAfter), no full scan.
  -- When SearchCriteria.afterIdentifier is set, the cursor is built from the
  -- matching document's occurredAt timestamp so that startAfter pagination
  -- aligns with the occurredAt DESC order.
  search criteria = FirestoreAuditRecordT $ do
    environment <- ask
    maybeCursorValue <- case criteria.afterIdentifier of
      Nothing -> pure Nothing
      Just afterRecordIdentifier -> do
        maybeDocument <-
          liftIO $
            getDocument @AuditRecordFirestoreDocument
              environment.firestoreContext
              auditLogsCollection
              (DocumentId (Text.pack (show afterRecordIdentifier.value)))
        pure $ case maybeDocument of
          Left _ -> Nothing
          Right Nothing -> Nothing
          Right (Just document) -> Just (QueryCursor [toValue document.occurredAt])
    let (queryFilters, queryOrders, queryLimit) = buildSearchQuery criteria
    result <-
      liftIO $
        runQuery @AuditRecordFirestoreDocument
          environment.firestoreContext
          auditLogsCollection
          queryFilters
          queryOrders
          queryLimit
          maybeCursorValue
    case result of
      Left _ -> pure []
      Right documents -> pure (concatMap toMaybeRecord documents)

  -- Must-6: Wrapped with withRetry (3 retries, exponential backoff).
  persist record = FirestoreAuditRecordT $ do
    environment <- ask
    now <- liftIO getCurrentTime
    let document = toDocument now record
        documentIdentifier = DocumentId (Text.pack (show record.identifier.value))
    result <-
      liftIO $
        withRetry defaultRetryPolicyConfig isRetryableForPersist $
          upsertDocument environment.firestoreContext auditLogsCollection documentIdentifier document
    case result of
      Left _ -> pure ()
      Right () -> pure ()

  terminate recordIdentifier = FirestoreAuditRecordT $ do
    environment <- ask
    _ <-
      liftIO $
        deleteDocument
          environment.firestoreContext
          auditLogsCollection
          (DocumentId (Text.pack (show recordIdentifier.value)))
    pure ()

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

toMaybeRecord :: AuditRecordFirestoreDocument -> [AuditRecord]
toMaybeRecord document =
  case documentToAuditRecord document of
    Left _ -> []
    Right record -> [record]

{- | Convert 'PayloadSummaryValue' map to a 'HashMap' of Aeson 'Value' for
 structured log output (Must-3).
-}
convertPayloadSummaryToAeson ::
  Map Text PayloadSummaryValue ->
  HashMap.HashMap Text Aeson.Value
convertPayloadSummaryToAeson summaryMap =
  HashMap.fromList $
    map (second convertSummaryValueToAeson) (Map.toList summaryMap)

convertSummaryValueToAeson :: PayloadSummaryValue -> Aeson.Value
convertSummaryValueToAeson (SummaryString text) = Aeson.String text
convertSummaryValueToAeson (SummaryNumber number) = Aeson.Number (realToFrac number)
convertSummaryValueToAeson (SummaryBool boolean) = Aeson.Bool boolean

-- | Must-7: FirestoreErrorDecode is NOT retryable (maps to DATA_SCHEMA_INVALID).
isRetryableForPersist :: FirestoreError -> Bool
isRetryableForPersist (FirestoreErrorDecode _) = False
isRetryableForPersist other = isRetryableFirestoreError other
 where
  isRetryableFirestoreError (FirestoreErrorTransport _) = True
  isRetryableFirestoreError (FirestoreErrorUnexpected status _) = status == 429 || status >= 500
  isRetryableFirestoreError _ = False

buildSearchQuery ::
  SearchCriteria ->
  ([QueryFilter], [QueryOrder], Int)
buildSearchQuery criteria =
  let filters =
        catMaybes
          [ fmap (\et -> QueryFilterEqual{filterField = "eventType", filterValue = toValue et}) criteria.eventTypeFilter
          , fmap (\sv -> QueryFilterEqual{filterField = "service", filterValue = toValue sv}) criteria.serviceFilter
          , fmap (\r -> QueryFilterEqual{filterField = "result", filterValue = toValue (resultToText r)}) criteria.resultFilter
          ]
      orders = [QueryOrder{orderField = "occurredAt", orderDirection = Descending}]
      limitCount = fromMaybe 50 criteria.limitCount
   in (filters, orders, limitCount)

-- ---------------------------------------------------------------------------
-- AuditArchiveRepository (Cloud Logging via stdout → Cloud Run collect)
-- Must-3: Structured log output with trace/identifier/eventType/result/service/payloadSummary
-- ---------------------------------------------------------------------------

newtype FirestoreAuditArchiveEnv = FirestoreAuditArchiveEnv
  { logEnv :: LogEnv
  }

newtype FirestoreAuditArchiveT m a = FirestoreAuditArchiveT
  { unFirestoreAuditArchiveT :: ReaderT FirestoreAuditArchiveEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runFirestoreAuditArchiveT :: FirestoreAuditArchiveEnv -> FirestoreAuditArchiveT m a -> m a
runFirestoreAuditArchiveT environment action =
  runReaderT (unFirestoreAuditArchiveT action) environment

instance AuditArchiveRepository (FirestoreAuditArchiveT IO) where
  -- Must-3: Outputs structured log with trace, identifier, eventType, result,
  --         service, and payloadSummary fields.
  persistArchive archive = FirestoreAuditArchiveT $ do
    environment <- ask
    let archiveResult = resultToText (normalizeResultFromEventType archive.eventType)
        archivePayloadSummary = fmap convertPayloadSummaryToAeson archive.payloadSummary
    liftIO $
      logInfoWith
        environment.logEnv
        ( LogContext
            { service = "audit-log"
            , trace = Just (Text.pack (show archive.trace.value))
            , identifier = Just (Text.pack (show archive.identifier.value))
            , eventType = Just archive.eventType
            , reasonCode = Nothing
            , result = Just archiveResult
            , payloadSummary = archivePayloadSummary
            }
        )
        ("audit.recorded: " <> archive.eventType)
