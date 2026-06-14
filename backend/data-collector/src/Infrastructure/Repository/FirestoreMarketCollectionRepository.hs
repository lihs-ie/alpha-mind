{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'MarketCollectionRepository'.

Must-10: FirestoreMarketCollectionRepositoryT newtype wrapping ReaderT.
Must-11: All 5 methods (find, findByStatus, search, persist, terminate) with withRetry on persist.
Must-12: Collection = market_collections, documentId = identifier.value (ULID string).
Must-13: FirestoreMarketCollectionEnv holds firestoreContext; isRetryableForPersist defined.
-}
module Infrastructure.Repository.FirestoreMarketCollectionRepository (
  -- * Environment
  FirestoreMarketCollectionEnv (..),

  -- * Monad transformer
  FirestoreMarketCollectionRepositoryT (..),
  runFirestoreMarketCollectionRepositoryT,

  -- * Retry predicate (exported for tests)
  isRetryableForPersist,

  -- * Codec (exported for pure round-trip tests — TC-INFRA-004-pure)
  MarketCollectionDocument (..),
  toDocument,
  documentToCollection,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.Int (Int64)
import Data.Maybe (catMaybes, fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (Day, UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (
  CollectionRequestSnapshot (..),
  CollectionSearchCriteria (..),
  CollectionStatus (..),
  MarketCollection,
  MarketCollectionIdentifier (..),
  MarketCollectionRepository (..),
  MarketSourceStatus (..),
  RequestedBy (..),
  SourceStatus (..),
  recordCollectionFailure,
  recordCollectionSuccess,
  startCollection,
 )
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.Wire.ReasonCodeWire (reasonCodeToWire)
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext,
  FirestoreError (..),
  FromFirestore (..),
  FromFirestoreValue (..),
  QueryFilter (..),
  QueryOrder (..),
  SortDirection (..),
  ToFirestore (..),
  ToFirestoreValue (..),
  deleteDocument,
  getDocument,
  requireField,
  runQuery,
  upsertDocument,
 )
import Resilience.Retry (defaultRetryPolicyConfig, withRetry)
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreMarketCollectionEnv = FirestoreMarketCollectionEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreMarketCollectionRepositoryT m a = FirestoreMarketCollectionRepositoryT
  { unFirestoreMarketCollectionRepositoryT :: ReaderT FirestoreMarketCollectionEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runFirestoreMarketCollectionRepositoryT ::
  FirestoreMarketCollectionEnv ->
  FirestoreMarketCollectionRepositoryT m a ->
  m a
runFirestoreMarketCollectionRepositoryT environment action =
  runReaderT (unFirestoreMarketCollectionRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

marketCollectionsCollection :: CollectionName
marketCollectionsCollection = CollectionName "market_collections"

-- ---------------------------------------------------------------------------
-- Firestore document codec
-- ---------------------------------------------------------------------------

data MarketCollectionDocument = MarketCollectionDocument
  { identifier :: ULID
  , collectionStatus :: Text
  , trace :: ULID
  , storagePath :: Maybe Text
  , jpSourceStatus :: Text
  , usSourceStatus :: Text
  , rowCount :: Maybe Int64
  , failureDetail :: Maybe Text
  , updatedAt :: UTCTime
  , targetDate :: Text
  }

instance ToFirestore MarketCollectionDocument where
  toFirestoreFields document =
    HashMap.fromList $
      [ ("identifier", toValue document.identifier)
      , ("collectionStatus", toValue document.collectionStatus)
      , ("trace", toValue document.trace)
      , ("jpSourceStatus", toValue document.jpSourceStatus)
      , ("usSourceStatus", toValue document.usSourceStatus)
      , ("updatedAt", toValue document.updatedAt)
      , ("targetDate", toValue document.targetDate)
      ]
        <> maybe [] (\path -> [("storagePath", toValue path)]) document.storagePath
        <> maybe [] (\count -> [("rowCount", toValue count)]) document.rowCount
        <> maybe [] (\detail -> [("failureDetail", toValue detail)]) document.failureDetail

instance FromFirestore MarketCollectionDocument where
  fromFirestoreFields fields = do
    identifierValue <- requireField "identifier" fields
    collectionStatusValue <- requireField "collectionStatus" fields
    traceValue <- requireField "trace" fields
    storagePathValue <- optionalField "storagePath" fields
    jpSourceStatusValue <- requireField "jpSourceStatus" fields
    usSourceStatusValue <- requireField "usSourceStatus" fields
    rowCountValue <- optionalField "rowCount" fields
    failureDetailValue <- optionalField "failureDetail" fields
    updatedAtValue <- requireField "updatedAt" fields
    targetDateValue <- requireField "targetDate" fields
    Right
      MarketCollectionDocument
        { identifier = identifierValue
        , collectionStatus = collectionStatusValue
        , trace = traceValue
        , storagePath = storagePathValue
        , jpSourceStatus = jpSourceStatusValue
        , usSourceStatus = usSourceStatusValue
        , rowCount = rowCountValue
        , failureDetail = failureDetailValue
        , updatedAt = updatedAtValue
        , targetDate = targetDateValue
        }

-- ---------------------------------------------------------------------------
-- Codec helpers
-- ---------------------------------------------------------------------------

optionalField ::
  (FromFirestoreValue a) =>
  Text ->
  HashMap Text GogolFireStore.Value ->
  Either Text (Maybe a)
optionalField key fields =
  case HashMap.lookup key fields of
    Nothing -> Right Nothing
    Just value -> case value.nullValue of
      Just _ -> Right Nothing
      Nothing -> fmap Just (extractValue key value)

collectionStatusToText :: CollectionStatus -> Text
collectionStatusToText Pending = "pending"
collectionStatusToText Collected = "collected"
collectionStatusToText Failed = "failed"

marketSourceStatusToText :: MarketSourceStatus -> Text
marketSourceStatusToText Ok = "ok"
marketSourceStatusToText SourceFailed = "failed"

marketSourceStatusFromText :: Text -> Either Text MarketSourceStatus
marketSourceStatusFromText "ok" = Right Ok
marketSourceStatusFromText "failed" = Right SourceFailed
marketSourceStatusFromText other = Left ("unknown sourceStatus: " <> other)

reasonCodeFromText :: Text -> Either Text ReasonCode
reasonCodeFromText "REQUEST_VALIDATION_FAILED" = Right RequestValidationFailed
reasonCodeFromText "COMPLIANCE_SOURCE_UNAPPROVED" = Right ComplianceSourceUnapproved
reasonCodeFromText "DATA_SOURCE_TIMEOUT" = Right DataSourceTimeout
reasonCodeFromText "DATA_SOURCE_UNAVAILABLE" = Right DataSourceUnavailable
reasonCodeFromText "DATA_SCHEMA_INVALID" = Right DataSchemaInvalid
reasonCodeFromText "IDEMPOTENCY_DUPLICATE_EVENT" = Right IdempotencyDuplicateEvent
reasonCodeFromText "STATE_CONFLICT" = Right StateConflict
reasonCodeFromText "DEPENDENCY_TIMEOUT" = Right DependencyTimeout
reasonCodeFromText other = Left ("unknown reasonCode: " <> other)

toDocument :: UTCTime -> MarketCollection -> MarketCollectionDocument
toDocument now collection =
  let statusText = collectionStatusToText collection.status
      traceUlid = collection.trace.value
      jpStatus = case collection.sourceStatus of
        Nothing -> marketSourceStatusToText Ok
        Just sourceStatus -> marketSourceStatusToText sourceStatus.jp
      usStatus = case collection.sourceStatus of
        Nothing -> marketSourceStatusToText Ok
        Just sourceStatus -> marketSourceStatusToText sourceStatus.us
      targetDateText = Text.pack (show collection.targetDate)
      rowCountInt64 = fmap (fromIntegral :: Int -> Int64) collection.rowCount
   in MarketCollectionDocument
        { identifier = collection.identifier.value
        , collectionStatus = statusText
        , trace = traceUlid
        , storagePath = collection.storagePath
        , jpSourceStatus = jpStatus
        , usSourceStatus = usStatus
        , rowCount = rowCountInt64
        , failureDetail = fmap reasonCodeToWire collection.reasonCode
        , updatedAt = now
        , targetDate = targetDateText
        }

documentToCollection :: MarketCollectionDocument -> Either Text MarketCollection
documentToCollection document = do
  jpStatus <- marketSourceStatusFromText document.jpSourceStatus
  usStatus <- marketSourceStatusFromText document.usSourceStatus
  targetDay <-
    maybe
      (Left ("invalid targetDate: " <> document.targetDate))
      Right
      (readMaybe (Text.unpack document.targetDate) :: Maybe Day)
  let collectionIdentifier = MarketCollectionIdentifier{value = document.identifier}
      traceValue = Trace{value = document.trace}
      sourceStatus = SourceStatus{jp = jpStatus, us = usStatus}
      snapshot =
        CollectionRequestSnapshot
          { targetDate = targetDay
          , requestedBy = Scheduler
          , mode = Nothing
          }
      (baseCollection, _) = startCollection collectionIdentifier snapshot traceValue
  -- Reconstruct state via domain commands
  case document.collectionStatus of
    "pending" -> Right baseCollection
    "collected" ->
      case document.storagePath of
        Nothing -> Left "collected document missing storagePath"
        Just path -> do
          let rowCountInt = maybe 0 fromIntegral document.rowCount
          let updatedAtValue = document.updatedAt
          case recordCollectionSuccess path sourceStatus rowCountInt updatedAtValue baseCollection of
            Left domainError -> Left (Text.pack (show domainError))
            Right (collection, _) -> Right collection
    "failed" -> do
      reasonCode <- case document.failureDetail of
        Nothing -> Right DependencyTimeout
        Just detail -> reasonCodeFromText detail
      case recordCollectionFailure reasonCode Nothing document.updatedAt baseCollection of
        Left domainError -> Left (Text.pack (show domainError))
        Right (collection, _) -> Right collection
    other -> Left ("unknown collectionStatus: " <> other)

-- ---------------------------------------------------------------------------
-- MarketCollectionRepository instance
-- Must-11: All 5 methods implemented.
-- ---------------------------------------------------------------------------

instance MarketCollectionRepository (FirestoreMarketCollectionRepositoryT IO) where
  find collectionIdentifier = FirestoreMarketCollectionRepositoryT $ do
    environment <- ask
    result <-
      liftIO $
        getDocument @MarketCollectionDocument
          environment.firestoreContext
          marketCollectionsCollection
          (DocumentId (Text.pack (show collectionIdentifier.value)))
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just document) ->
        pure $ case documentToCollection document of
          Left _ -> Nothing
          Right collection -> Just collection

  findByStatus status = FirestoreMarketCollectionRepositoryT $ do
    environment <- ask
    result <-
      liftIO $
        runQuery @MarketCollectionDocument
          environment.firestoreContext
          marketCollectionsCollection
          [QueryFilterEqual{filterField = "collectionStatus", filterValue = toValue (collectionStatusToText status)}]
          [QueryOrder{orderField = "updatedAt", orderDirection = Descending}]
          100
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (concatMap toMaybeCollection documents)

  search criteria = FirestoreMarketCollectionRepositoryT $ do
    environment <- ask
    let filters =
          catMaybes
            [ fmap
                ( \s ->
                    QueryFilterEqual
                      { filterField = "collectionStatus"
                      , filterValue = toValue (collectionStatusToText s)
                      }
                )
                criteria.statusFilter
            ]
        orders = [QueryOrder{orderField = "updatedAt", orderDirection = Descending}]
        limitCount = fromMaybe 50 criteria.limitCount
    result <-
      liftIO $
        runQuery @MarketCollectionDocument
          environment.firestoreContext
          marketCollectionsCollection
          filters
          orders
          limitCount
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (concatMap toMaybeCollection documents)

  -- Must-11: withRetry wraps upsertDocument (note: upsertDocument is already retried internally;
  -- outer withRetry matches audit-log pattern for consistency — see impact-map §齟齬2)
  persist collection = FirestoreMarketCollectionRepositoryT $ do
    environment <- ask
    now <- liftIO getCurrentTime
    let document = toDocument now collection
        documentIdentifier = DocumentId (Text.pack (show collection.identifier.value))
    _ <-
      liftIO $
        withRetry defaultRetryPolicyConfig isRetryableForPersist $
          upsertDocument environment.firestoreContext marketCollectionsCollection documentIdentifier document
    pure ()

  terminate collectionIdentifier = FirestoreMarketCollectionRepositoryT $ do
    environment <- ask
    _ <-
      liftIO $
        deleteDocument
          environment.firestoreContext
          marketCollectionsCollection
          (DocumentId (Text.pack (show collectionIdentifier.value)))
    pure ()

-- ---------------------------------------------------------------------------
-- Retry predicate (Must-13)
-- ---------------------------------------------------------------------------

{- | FirestoreErrorDecode is NOT retryable (DATA_SCHEMA_INVALID).
Transport and 5xx/429 errors are retryable.
-}
isRetryableForPersist :: FirestoreError -> Bool
isRetryableForPersist (FirestoreErrorDecode _) = False
isRetryableForPersist other = isRetryableError other
 where
  isRetryableError (FirestoreErrorTransport _) = True
  isRetryableError (FirestoreErrorUnexpected status _) = status == 429 || status >= 500
  isRetryableError _ = False

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

toMaybeCollection :: MarketCollectionDocument -> [MarketCollection]
toMaybeCollection document =
  case documentToCollection document of
    Left _ -> []
    Right collection -> [collection]
