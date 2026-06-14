{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'InsightCollectionRepository'.

Must-INFRA-011: FirestoreInsightCollectionRepositoryT newtype wrapping ReaderT.
Must-INFRA-012: persistCollection upserts to insight_collections; documentId = identifier.value (ULID string).
Must-INFRA-013: findCollection retrieves by identifier.
Must-INFRA-014: findByStatus queries by status field.
Must-INFRA-015: searchCollections supports status filter with limit.
Must-INFRA-016: terminateCollectionRecord deletes the document from Firestore.
Must-INFRA-017: isRetryableForPersist — FirestoreErrorTransport and 429/5xx are retryable.
-}
module Infrastructure.Repository.FirestoreInsightCollectionRepository (
  -- * Environment
  FirestoreInsightCollectionEnv (..),

  -- * Monad transformer
  FirestoreInsightCollectionRepositoryT (..),
  runFirestoreInsightCollectionRepositoryT,

  -- * Retry predicate (exported for tests)
  isRetryableForPersist,

  -- * Codec (exported for pure round-trip tests)
  InsightCollectionDocument (..),
  toDocument,
  documentToCollection,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.HashMap.Strict qualified as HashMap
import Data.Maybe (fromMaybe, mapMaybe, maybeToList)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime, parseTimeM)
import Data.ULID (ULID)
import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (
  CollectionSearchCriteria (..),
  CollectionStatus (..),
  InsightCollection,
  InsightCollectionIdentifier (..),
  InsightCollectionRepository (..),
  InsightCollectionRequestSnapshot (..),
  RequestedBy (..),
  mkInsightCollectionRequestSnapshot,
  startCollection,
 )
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext,
  FirestoreError (..),
  FromFirestore (..),
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

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreInsightCollectionEnv = FirestoreInsightCollectionEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreInsightCollectionRepositoryT m a = FirestoreInsightCollectionRepositoryT
  { unFirestoreInsightCollectionRepositoryT :: ReaderT FirestoreInsightCollectionEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runFirestoreInsightCollectionRepositoryT ::
  FirestoreInsightCollectionEnv ->
  FirestoreInsightCollectionRepositoryT m a ->
  m a
runFirestoreInsightCollectionRepositoryT environment action =
  runReaderT (unFirestoreInsightCollectionRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

insightCollectionsCollection :: CollectionName
insightCollectionsCollection = CollectionName "insight_collections"

-- ---------------------------------------------------------------------------
-- Retry predicate
-- ---------------------------------------------------------------------------

-- | Must-INFRA-017: Transport errors and HTTP 429/5xx are retryable.
isRetryableForPersist :: FirestoreError -> Bool
isRetryableForPersist (FirestoreErrorTransport _) = True
isRetryableForPersist (FirestoreErrorUnexpected statusCode _) = statusCode == 429 || statusCode >= 500
isRetryableForPersist _ = False

-- ---------------------------------------------------------------------------
-- Firestore document codec
-- ---------------------------------------------------------------------------

data InsightCollectionDocument = InsightCollectionDocument
  { identifier :: ULID
  , status :: Text
  , targetDate :: Text
  , requestedBy :: Text
  , traceValue :: ULID
  , updatedAt :: UTCTime
  }

instance ToFirestore InsightCollectionDocument where
  toFirestoreFields document =
    HashMap.fromList
      [ ("identifier", toValue document.identifier)
      , ("status", toValue document.status)
      , ("targetDate", toValue document.targetDate)
      , ("requestedBy", toValue document.requestedBy)
      , ("trace", toValue document.traceValue)
      , ("updatedAt", toValue document.updatedAt)
      ]

instance FromFirestore InsightCollectionDocument where
  fromFirestoreFields fields = do
    identifierValue <- requireField "identifier" fields
    statusValue <- requireField "status" fields
    targetDateValue <- requireField "targetDate" fields
    requestedByValue <- requireField "requestedBy" fields
    traceVal <- requireField "trace" fields
    updatedAtValue <- requireField "updatedAt" fields
    Right
      InsightCollectionDocument
        { identifier = identifierValue
        , status = statusValue
        , targetDate = targetDateValue
        , requestedBy = requestedByValue
        , traceValue = traceVal
        , updatedAt = updatedAtValue
        }

-- ---------------------------------------------------------------------------
-- Codec helpers
-- ---------------------------------------------------------------------------

statusToText :: CollectionStatus -> Text
statusToText Pending = "pending"
statusToText Collected = "collected"
statusToText Failed = "failed"

requestedByToText :: RequestedBy -> Text
requestedByToText Scheduler = "scheduler"
requestedByToText User = "user"

requestedByFromText :: Text -> Either Text RequestedBy
requestedByFromText "scheduler" = Right Scheduler
requestedByFromText "user" = Right User
requestedByFromText other = Left ("unknown RequestedBy: " <> other)

toDocument :: UTCTime -> InsightCollection -> InsightCollectionDocument
toDocument now collection =
  InsightCollectionDocument
    { identifier = collection.identifier.value
    , status = statusToText collection.status
    , targetDate = Text.pack (formatTime defaultTimeLocale "%Y-%m-%d" collection.request.targetDate)
    , requestedBy = requestedByToText collection.request.requestedBy
    , traceValue = collection.identifier.value
    , updatedAt = now
    }

documentToCollection :: InsightCollectionDocument -> Either Text InsightCollection
documentToCollection document = do
  requestedByValue <- requestedByFromText document.requestedBy
  targetDateValue <-
    maybe
      (Left ("invalid targetDate format: " <> document.targetDate))
      Right
      (parseTimeM True defaultTimeLocale "%Y-%m-%d" (Text.unpack document.targetDate))
  let collectionIdentifier = InsightCollectionIdentifier{value = document.identifier}
      traceValue = Trace{value = document.traceValue}
  case mkInsightCollectionRequestSnapshot targetDateValue requestedByValue [] Nothing of
    Left domainError -> Left (Text.pack (show domainError))
    Right snapshot ->
      case startCollection collectionIdentifier traceValue snapshot of
        Left domainError -> Left (Text.pack (show domainError))
        Right collection -> Right collection

-- ---------------------------------------------------------------------------
-- Port implementation
-- ---------------------------------------------------------------------------

instance InsightCollectionRepository (FirestoreInsightCollectionRepositoryT IO) where
  findCollection collectionIdentifier = FirestoreInsightCollectionRepositoryT $ do
    environment <- ask
    liftIO $ do
      let documentIdentifier = DocumentId (Text.pack (show collectionIdentifier.value))
      result <-
        getDocument
          environment.firestoreContext
          insightCollectionsCollection
          documentIdentifier
      case result of
        Left firestoreError -> fail ("findCollection failed: " <> show firestoreError)
        Right Nothing -> pure Nothing
        Right (Just document) ->
          case documentToCollection document of
            Left _ -> pure Nothing
            Right collection -> pure (Just collection)

  findByStatus collectionStatus = FirestoreInsightCollectionRepositoryT $ do
    environment <- ask
    result <-
      liftIO $
        runQuery @InsightCollectionDocument
          environment.firestoreContext
          insightCollectionsCollection
          [QueryFilterEqual{filterField = "status", filterValue = toValue (statusToText collectionStatus)}]
          [QueryOrder{orderField = "updatedAt", orderDirection = Descending}]
          100
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (mapMaybe (either (const Nothing) Just . documentToCollection) documents)

  searchCollections criteria = FirestoreInsightCollectionRepositoryT $ do
    environment <- ask
    let filters =
          mapMaybe
            ( \s ->
                Just
                  QueryFilterEqual
                    { filterField = "status"
                    , filterValue = toValue (statusToText s)
                    }
            )
            (maybeToList criteria.statusFilter)
        orders = [QueryOrder{orderField = "updatedAt", orderDirection = Descending}]
        limitValue = fromMaybe 50 criteria.limitCount
    result <-
      liftIO $
        runQuery @InsightCollectionDocument
          environment.firestoreContext
          insightCollectionsCollection
          filters
          orders
          limitValue
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (mapMaybe (either (const Nothing) Just . documentToCollection) documents)

  persistCollection collection = FirestoreInsightCollectionRepositoryT $ do
    environment <- ask
    liftIO $ do
      now <- getCurrentTime
      let document = toDocument now collection
          documentIdentifier = DocumentId (Text.pack (show collection.identifier.value))
      result <-
        withRetry defaultRetryPolicyConfig isRetryableForPersist $
          upsertDocument environment.firestoreContext insightCollectionsCollection documentIdentifier document
      case result of
        Left firestoreError -> fail ("persistCollection failed: " <> show firestoreError)
        Right () -> pure ()

  terminateCollectionRecord collectionIdentifier = FirestoreInsightCollectionRepositoryT $ do
    environment <- ask
    liftIO $ do
      let documentIdentifier = DocumentId (Text.pack (show collectionIdentifier.value))
      result <-
        deleteDocument environment.firestoreContext insightCollectionsCollection documentIdentifier
      case result of
        Left firestoreError -> fail ("terminateCollectionRecord failed: " <> show firestoreError)
        Right () -> pure ()
