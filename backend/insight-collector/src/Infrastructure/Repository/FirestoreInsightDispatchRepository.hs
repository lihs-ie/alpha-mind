{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'InsightDispatchRepository'.

Must-12: InsightDispatch を idempotency_keys/{identifier} に永続化する。
  - collection: idempotency_keys（共有 Persistence.Idempotency が使用するコレクションと同一）
  - documentId: identifier.value (ULID string)
  - fields: identifier, dispatchStatus, decisionStatus, publishedEvent, reasonCode, trace, processedAt, updatedAt
  - RULE-IC-004 / RULE-IC-005: 同一イベント identifier は1回のみ published へ遷移。
-}
module Infrastructure.Repository.FirestoreInsightDispatchRepository (
  -- * Environment
  FirestoreInsightDispatchEnv (..),

  -- * Monad transformer
  FirestoreInsightDispatchRepositoryT (..),
  runFirestoreInsightDispatchRepositoryT,

  -- * Retry predicate (exported for tests)
  isRetryableForPersist,

  -- * Codec (exported for pure round-trip tests)
  InsightDispatchDocument (..),
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
import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (InsightCollectionIdentifier (..))
import Domain.InsightCollection.InsightDispatch (
  DispatchDecision (..),
  DispatchStatus (..),
  InsightDispatch,
  InsightDispatchRepository (..),
  PublishedEventType (..),
  markDispatchFailed,
  markDispatched,
  startDispatch,
 )
import Domain.InsightCollection.ReasonCode (ReasonCode)
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.Wire.ReasonCodeWire (reasonCodeFromWire, reasonCodeToWire)
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

newtype FirestoreInsightDispatchEnv = FirestoreInsightDispatchEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreInsightDispatchRepositoryT m a = FirestoreInsightDispatchRepositoryT
  { unFirestoreInsightDispatchRepositoryT :: ReaderT FirestoreInsightDispatchEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runFirestoreInsightDispatchRepositoryT ::
  FirestoreInsightDispatchEnv ->
  FirestoreInsightDispatchRepositoryT m a ->
  m a
runFirestoreInsightDispatchRepositoryT environment action =
  runReaderT (unFirestoreInsightDispatchRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Collection constant
-- Must-12: idempotency_keys/{identifier} に永続化
-- ---------------------------------------------------------------------------

insightDispatchCollection :: CollectionName
insightDispatchCollection = CollectionName "idempotency_keys"

-- ---------------------------------------------------------------------------
-- Firestore document codec
-- ---------------------------------------------------------------------------

data InsightDispatchDocument = InsightDispatchDocument
  { identifier :: ULID
  , dispatchStatus :: Text
  , decisionStatus :: Text
  , publishedEvent :: Maybe Text
  , reasonCode :: Maybe Text
  , trace :: ULID
  , processedAt :: Maybe UTCTime
  , updatedAt :: UTCTime
  }

instance ToFirestore InsightDispatchDocument where
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

instance FromFirestore InsightDispatchDocument where
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
      InsightDispatchDocument
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
publishedEventToText InsightCollected = "insight.collected"
publishedEventToText InsightCollectFailed = "insight.collect.failed"

publishedEventFromText :: Text -> Either Text PublishedEventType
publishedEventFromText "insight.collected" = Right InsightCollected
publishedEventFromText "insight.collect.failed" = Right InsightCollectFailed
publishedEventFromText other = Left ("unknown publishedEvent: " <> other)

-- ---------------------------------------------------------------------------
-- Codec: domain ↔ document
-- ---------------------------------------------------------------------------

toDocument :: UTCTime -> InsightDispatch -> InsightDispatchDocument
toDocument now dispatch =
  let decision = dispatch.dispatchDecision
   in InsightDispatchDocument
        { identifier = dispatch.identifier.value
        , dispatchStatus = dispatchStatusToText dispatch.dispatchStatus
        , decisionStatus = dispatchStatusToText decision.dispatchStatus
        , publishedEvent = fmap publishedEventToText decision.publishedEvent
        , reasonCode = fmap reasonCodeToWire decision.reasonCode
        , trace = dispatch.trace.value
        , processedAt = dispatch.processedAt
        , updatedAt = now
        }

documentToDispatch :: InsightDispatchDocument -> Either Text InsightDispatch
documentToDispatch document = do
  let collectionIdentifier = InsightCollectionIdentifier{value = document.identifier}
      traceValue = Trace{value = document.trace}
      baseDispatch = startDispatch collectionIdentifier traceValue
  case document.dispatchStatus of
    "pending" -> Right baseDispatch
    "published" -> do
      publishedEventType <- case document.publishedEvent of
        Nothing -> Right InsightCollected
        Just eventText -> publishedEventFromText eventText
      processedTime <-
        maybe (Left "published dispatch missing processedAt") Right document.processedAt
      case markDispatched publishedEventType processedTime baseDispatch of
        Left domainError -> Left (Text.pack (show domainError))
        Right dispatch -> Right dispatch
    "failed" -> do
      reasonCodeValue <- case document.reasonCode of
        Nothing -> Left "failed dispatch missing reasonCode"
        Just codeText -> reasonCodeFromWire codeText
      processedTime <-
        maybe (Left "failed dispatch missing processedAt") Right document.processedAt
      case markDispatchFailed reasonCodeValue processedTime baseDispatch of
        Left domainError -> Left (Text.pack (show domainError))
        Right dispatch -> Right dispatch
    other -> Left ("unknown dispatchStatus: " <> other)

-- ---------------------------------------------------------------------------
-- InsightDispatchRepository instance
-- ---------------------------------------------------------------------------

instance InsightDispatchRepository (FirestoreInsightDispatchRepositoryT IO) where
  findDispatch collectionIdentifier = FirestoreInsightDispatchRepositoryT $ do
    environment <- ask
    result <-
      liftIO $
        getDocument @InsightDispatchDocument
          environment.firestoreContext
          insightDispatchCollection
          (DocumentId (Text.pack (show collectionIdentifier.value)))
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just document) ->
        pure $ case documentToDispatch document of
          Left _ -> Nothing
          Right dispatch -> Just dispatch

  persistDispatch dispatch = FirestoreInsightDispatchRepositoryT $ do
    environment <- ask
    now <- liftIO getCurrentTime
    let document = toDocument now dispatch
        documentIdentifier = DocumentId (Text.pack (show dispatch.identifier.value))
    _ <-
      liftIO $
        withRetry defaultRetryPolicyConfig isRetryableForPersist $
          upsertDocument
            environment.firestoreContext
            insightDispatchCollection
            documentIdentifier
            document
    pure ()

  terminateDispatch' collectionIdentifier = FirestoreInsightDispatchRepositoryT $ do
    environment <- ask
    _ <-
      liftIO $
        deleteDocument
          environment.firestoreContext
          insightDispatchCollection
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
isRetryableForPersist (FirestoreErrorTransport _) = True
isRetryableForPersist (FirestoreErrorUnexpected statusCode _) =
  statusCode == 429 || statusCode >= 500
isRetryableForPersist _ = False
