{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'CollectionDispatchRepository'.

Must-14: FirestoreCollectionDispatchRepositoryT newtype wrapping ReaderT.
Must-15: All 3 methods (find, persist, terminate) with withRetry on persist.
Must-16: Collection = collection_dispatches, documentId = identifier.value (ULID).
         Fields: identifier, dispatchStatus, dispatchDecision (status/publishedEvent/reasonCode), trace, processedAt, updatedAt.
-}
module Infrastructure.Repository.FirestoreCollectionDispatchRepository (
  -- * Environment
  FirestoreCollectionDispatchEnv (..),

  -- * Monad transformer
  FirestoreCollectionDispatchRepositoryT (..),
  runFirestoreCollectionDispatchRepositoryT,

  -- * Retry predicate (exported for tests)
  isRetryableForPersist,

  -- * Codec (exported for pure round-trip tests — TC-INFRA-005-pure)
  CollectionDispatchDocument (..),
  toDocument,
  documentToDispatch,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (MarketCollectionIdentifier (..))
import Domain.MarketCollection.CollectionDispatch (
  CollectionDispatch,
  CollectionDispatchRepository (..),
  DispatchDecision (..),
  DispatchStatus (..),
  PublishedEventType (..),
  markDispatchFailed,
  markDispatched,
  startDispatch,
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
  ToFirestore (..),
  ToFirestoreValue (..),
  deleteDocument,
  getDocument,
  requireField,
  upsertDocument,
 )
import Resilience.Retry (defaultRetryPolicyConfig, withRetry)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreCollectionDispatchEnv = FirestoreCollectionDispatchEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreCollectionDispatchRepositoryT m a = FirestoreCollectionDispatchRepositoryT
  { unFirestoreCollectionDispatchRepositoryT :: ReaderT FirestoreCollectionDispatchEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runFirestoreCollectionDispatchRepositoryT ::
  FirestoreCollectionDispatchEnv ->
  FirestoreCollectionDispatchRepositoryT m a ->
  m a
runFirestoreCollectionDispatchRepositoryT environment action =
  runReaderT (unFirestoreCollectionDispatchRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

collectionDispatchesCollection :: CollectionName
collectionDispatchesCollection = CollectionName "collection_dispatches"

-- ---------------------------------------------------------------------------
-- Firestore document codec
-- ---------------------------------------------------------------------------

data CollectionDispatchDocument = CollectionDispatchDocument
  { identifier :: ULID
  , dispatchStatus :: Text
  , decisionStatus :: Text
  , publishedEvent :: Maybe Text
  , reasonCode :: Maybe Text
  , trace :: ULID
  , processedAt :: Maybe UTCTime
  , updatedAt :: UTCTime
  }

instance ToFirestore CollectionDispatchDocument where
  toFirestoreFields document =
    HashMap.fromList $
      [ ("identifier", toValue document.identifier)
      , ("dispatchStatus", toValue document.dispatchStatus)
      , ("decisionStatus", toValue document.decisionStatus)
      , ("trace", toValue document.trace)
      , ("updatedAt", toValue document.updatedAt)
      ]
        <> maybe [] (\event -> [("publishedEvent", toValue event)]) document.publishedEvent
        <> maybe [] (\code -> [("reasonCode", toValue code)]) document.reasonCode
        <> maybe [] (\time -> [("processedAt", toValue time)]) document.processedAt

instance FromFirestore CollectionDispatchDocument where
  fromFirestoreFields fields = do
    identifierValue <- requireField "identifier" fields
    dispatchStatusValue <- requireField "dispatchStatus" fields
    decisionStatusValue <- requireField "decisionStatus" fields
    publishedEventValue <- optionalField "publishedEvent" fields
    reasonCodeValue <- optionalField "reasonCode" fields
    traceValue <- requireField "trace" fields
    processedAtValue <- optionalField "processedAt" fields
    updatedAtValue <- requireField "updatedAt" fields
    Right
      CollectionDispatchDocument
        { identifier = identifierValue
        , dispatchStatus = dispatchStatusValue
        , decisionStatus = decisionStatusValue
        , publishedEvent = publishedEventValue
        , reasonCode = reasonCodeValue
        , trace = traceValue
        , processedAt = processedAtValue
        , updatedAt = updatedAtValue
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

dispatchStatusToText :: DispatchStatus -> Text
dispatchStatusToText Pending = "pending"
dispatchStatusToText Published = "published"
dispatchStatusToText Failed = "failed"

publishedEventToText :: PublishedEventType -> Text
publishedEventToText MarketCollected = "market.collected"
publishedEventToText MarketCollectFailed = "market.collect.failed"

publishedEventFromText :: Text -> Either Text PublishedEventType
publishedEventFromText "market.collected" = Right MarketCollected
publishedEventFromText "market.collect.failed" = Right MarketCollectFailed
publishedEventFromText other = Left ("unknown publishedEvent: " <> other)

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

toDocument :: UTCTime -> CollectionDispatch -> CollectionDispatchDocument
toDocument now dispatch =
  let decision = dispatch.dispatchDecision
   in CollectionDispatchDocument
        { identifier = dispatch.identifier.value
        , dispatchStatus = dispatchStatusToText dispatch.dispatchStatus
        , decisionStatus = dispatchStatusToText decision.dispatchStatus
        , publishedEvent = fmap publishedEventToText decision.publishedEvent
        , reasonCode = fmap reasonCodeToWire decision.reasonCode
        , trace = dispatch.trace.value
        , processedAt = dispatch.processedAt
        , updatedAt = now
        }

documentToDispatch :: CollectionDispatchDocument -> Either Text CollectionDispatch
documentToDispatch document = do
  let collectionIdentifier = MarketCollectionIdentifier{value = document.identifier}
      traceValue = Trace{value = document.trace}
      baseDispatch = startDispatch collectionIdentifier traceValue
  -- Reconstruct state via domain commands
  case document.dispatchStatus of
    "pending" -> Right baseDispatch
    "published" -> do
      publishedEventType <- case document.publishedEvent of
        Nothing -> Right MarketCollected
        Just eventText -> publishedEventFromText eventText
      processedTime <- maybe (Left "published dispatch missing processedAt") Right document.processedAt
      case markDispatched publishedEventType processedTime baseDispatch of
        Left domainError -> Left (Text.pack (show domainError))
        Right dispatch -> Right dispatch
    "failed" -> do
      reasonCode <- case document.reasonCode of
        Nothing -> Right DependencyTimeout
        Just codeText -> reasonCodeFromText codeText
      processedTime <- maybe (Left "failed dispatch missing processedAt") Right document.processedAt
      case markDispatchFailed reasonCode processedTime baseDispatch of
        Left domainError -> Left (Text.pack (show domainError))
        Right dispatch -> Right dispatch
    other -> Left ("unknown dispatchStatus: " <> other)

-- ---------------------------------------------------------------------------
-- CollectionDispatchRepository instance
-- Must-15: All 3 methods implemented.
-- ---------------------------------------------------------------------------

instance CollectionDispatchRepository (FirestoreCollectionDispatchRepositoryT IO) where
  find collectionIdentifier = FirestoreCollectionDispatchRepositoryT $ do
    environment <- ask
    result <-
      liftIO $
        getDocument @CollectionDispatchDocument
          environment.firestoreContext
          collectionDispatchesCollection
          (DocumentId (Text.pack (show collectionIdentifier.value)))
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just document) ->
        pure $ case documentToDispatch document of
          Left _ -> Nothing
          Right dispatch -> Just dispatch

  -- Must-15: withRetry wraps upsertDocument
  persist dispatch = FirestoreCollectionDispatchRepositoryT $ do
    environment <- ask
    now <- liftIO getCurrentTime
    let document = toDocument now dispatch
        documentIdentifier = DocumentId (Text.pack (show dispatch.identifier.value))
    _ <-
      liftIO $
        withRetry defaultRetryPolicyConfig isRetryableForPersist $
          upsertDocument environment.firestoreContext collectionDispatchesCollection documentIdentifier document
    pure ()

  terminate collectionIdentifier = FirestoreCollectionDispatchRepositoryT $ do
    environment <- ask
    _ <-
      liftIO $
        deleteDocument
          environment.firestoreContext
          collectionDispatchesCollection
          (DocumentId (Text.pack (show collectionIdentifier.value)))
    pure ()

-- ---------------------------------------------------------------------------
-- Retry predicate
-- ---------------------------------------------------------------------------

{- | FirestoreErrorDecode is NOT retryable.
Transport and 5xx/429 errors are retryable.
-}
isRetryableForPersist :: FirestoreError -> Bool
isRetryableForPersist (FirestoreErrorDecode _) = False
isRetryableForPersist other = isRetryableError other
 where
  isRetryableError (FirestoreErrorTransport _) = True
  isRetryableError (FirestoreErrorUnexpected status _) = status == 429 || status >= 500
  isRetryableError _ = False
