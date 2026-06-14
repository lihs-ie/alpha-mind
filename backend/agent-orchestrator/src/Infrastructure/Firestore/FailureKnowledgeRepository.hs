{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'FailureKnowledgeRepository'.

Must-10: find, findByReasonCode, search, persist implemented via injectable FirestoreTransport.
Must-11: createdAt written as RFC3339 (ISO8601 UTC) timestamp on persist.

Collection: @failure_knowledge@
Document ID: @identifier.value@ (ULID string)
-}
module Infrastructure.Firestore.FailureKnowledgeRepository (
  -- * Environment
  FirestoreFailureKnowledgeEnv (..),

  -- * Monad transformer
  FirestoreFailureKnowledgeRepositoryT (..),
  runFirestoreFailureKnowledgeRepositoryT,

  -- * Codec (exported for pure round-trip tests)
  knowledgeToFields,
  fieldsToKnowledge,
) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.Class (MonadTrans)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Either (rights)
import Data.HashMap.Strict qualified as HashMap
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.FailureKnowledge (
  FailureKnowledge (..),
  FailureKnowledgeIdentifier (..),
  FailureKnowledgeRepository (..),
  FailureKnowledgeSearchCriteria (..),
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.Firestore.Env (FirestoreEnv (..), FirestoreTransport (..))
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  QueryFilter (..),
  QueryOrder (..),
  SortDirection (..),
  ToFirestoreValue (..),
  requireField,
 )
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

failureKnowledgeCollection :: CollectionName
failureKnowledgeCollection = CollectionName "failure_knowledge"

defaultQueryLimit :: Int
defaultQueryLimit = 50

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreFailureKnowledgeEnv = FirestoreFailureKnowledgeEnv
  { firestoreEnv :: FirestoreEnv
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreFailureKnowledgeRepositoryT m a = FirestoreFailureKnowledgeRepositoryT
  { unFirestoreFailureKnowledgeRepositoryT :: ReaderT FirestoreFailureKnowledgeEnv m a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO, MonadTrans)

runFirestoreFailureKnowledgeRepositoryT ::
  FirestoreFailureKnowledgeEnv ->
  FirestoreFailureKnowledgeRepositoryT m a ->
  m a
runFirestoreFailureKnowledgeRepositoryT environment action =
  runReaderT (unFirestoreFailureKnowledgeRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- ReasonCode codec
-- ---------------------------------------------------------------------------

reasonCodeToText :: ReasonCode -> Text
reasonCodeToText ResourceNotFound = "RESOURCE_NOT_FOUND"
reasonCodeToText RequestValidationFailed = "REQUEST_VALIDATION_FAILED"
reasonCodeToText StateConflict = "STATE_CONFLICT"
reasonCodeToText IdempotencyDuplicateEvent = "IDEMPOTENCY_DUPLICATE_EVENT"
reasonCodeToText DependencyTimeout = "DEPENDENCY_TIMEOUT"
reasonCodeToText DependencyUnavailable = "DEPENDENCY_UNAVAILABLE"

reasonCodeFromText :: Text -> Either DomainError ReasonCode
reasonCodeFromText "RESOURCE_NOT_FOUND" = Right ResourceNotFound
reasonCodeFromText "REQUEST_VALIDATION_FAILED" = Right RequestValidationFailed
reasonCodeFromText "STATE_CONFLICT" = Right StateConflict
reasonCodeFromText "IDEMPOTENCY_DUPLICATE_EVENT" = Right IdempotencyDuplicateEvent
reasonCodeFromText "DEPENDENCY_TIMEOUT" = Right DependencyTimeout
reasonCodeFromText "DEPENDENCY_UNAVAILABLE" = Right DependencyUnavailable
reasonCodeFromText _other = Left (MissingRequiredFields ["reasonCode"] RequestValidationFailed)

-- ---------------------------------------------------------------------------
-- Firestore codec
-- ---------------------------------------------------------------------------

{- | Encode a 'FailureKnowledge' to Firestore field map.
Must-11: @createdAt@ is written as UTCTime (stored as RFC3339 via ToFirestoreValue UTCTime).
Exported for pure round-trip tests.
-}
knowledgeToFields :: FailureKnowledge -> HashMap.HashMap Text GogolFireStore.Value
knowledgeToFields knowledge =
  let FailureKnowledgeIdentifier knowledgeUlid = knowledge.identifier
   in HashMap.fromList
        [ ("identifier", toValue (Text.pack (show knowledgeUlid)))
        , ("reasonCode", toValue (reasonCodeToText knowledge.reasonCode))
        , ("summary", toValue knowledge.summary)
        , ("markdownSummary", toValue knowledge.markdownSummary)
        , ("similarityHash", toValue knowledge.similarityHash)
        , ("createdAt", toValue knowledge.recordedAt)
        ]

{- | Decode a Firestore field map to a 'FailureKnowledge'.
Exported for pure round-trip tests.
-}
fieldsToKnowledge :: HashMap.HashMap Text GogolFireStore.Value -> Either DomainError FailureKnowledge
fieldsToKnowledge fields = do
  identifierText <- liftTextError (requireField "identifier" fields)
  identifierUlid <- case readMaybe (Text.unpack identifierText) of
    Nothing -> Left (MissingRequiredFields ["identifier"] RequestValidationFailed)
    Just ulid -> Right (ulid :: ULID)
  reasonCodeText <- liftTextError (requireField "reasonCode" fields)
  reasonCodeValue <- reasonCodeFromText reasonCodeText
  summaryValue <- liftTextError (requireField "summary" fields)
  markdownSummaryValue <- liftTextError (requireField "markdownSummary" fields)
  similarityHashValue <- liftTextError (requireField "similarityHash" fields)
  createdAtValue <- liftTextError (requireField "createdAt" fields)
  Right
    FailureKnowledge
      { identifier = FailureKnowledgeIdentifier{value = identifierUlid}
      , reasonCode = reasonCodeValue
      , summary = summaryValue
      , markdownSummary = markdownSummaryValue
      , similarityHash = similarityHashValue
      , recordedAt = createdAtValue :: UTCTime
      }

liftTextError :: Either Text a -> Either DomainError a
liftTextError (Right x) = Right x
liftTextError (Left message) = Left (MissingRequiredFields [message] ResourceNotFound)

-- ---------------------------------------------------------------------------
-- FailureKnowledgeRepository instance (Must-10)
-- ---------------------------------------------------------------------------

instance FailureKnowledgeRepository (FirestoreFailureKnowledgeRepositoryT IO) where
  find knowledgeIdentifier = FirestoreFailureKnowledgeRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportGetDocument} = environment.firestoreEnv.firestoreExecute
        FailureKnowledgeIdentifier findUlid = knowledgeIdentifier
        documentId = DocumentId (Text.pack (show findUlid))
    result <- liftIO $ transportGetDocument failureKnowledgeCollection documentId
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just fieldMap) ->
        pure $ case fieldsToKnowledge fieldMap of
          Left _ -> Nothing
          Right knowledge -> Just knowledge

  findByReasonCode reasonCode = FirestoreFailureKnowledgeRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportRunQuery} = environment.firestoreEnv.firestoreExecute
        filters = [QueryFilterEqual{filterField = "reasonCode", filterValue = toValue (reasonCodeToText reasonCode)}]
        -- Composite index: similarityHash ASC, createdAt DESC (spec §FailureKnowledge)
        orders = [QueryOrder{orderField = "createdAt", orderDirection = Descending}]
    result <- liftIO $ transportRunQuery failureKnowledgeCollection filters orders defaultQueryLimit
    case result of
      Left _ -> pure []
      Right fieldMaps -> pure (rights (map fieldsToKnowledge fieldMaps))

  search criteria = FirestoreFailureKnowledgeRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportRunQuery} = environment.firestoreEnv.firestoreExecute
        limitValue = fromMaybe defaultQueryLimit criteria.limitCount
        reasonCodeFilters = case criteria.reasonCodeFilter of
          Nothing -> []
          Just code -> [QueryFilterEqual{filterField = "reasonCode", filterValue = toValue (reasonCodeToText code)}]
        hashFilters = case criteria.similarityHashFilter of
          Nothing -> []
          Just hashValue -> [QueryFilterEqual{filterField = "similarityHash", filterValue = toValue hashValue}]
        allFilters = reasonCodeFilters <> hashFilters
        orders = [QueryOrder{orderField = "createdAt", orderDirection = Descending}]
    result <- liftIO $ transportRunQuery failureKnowledgeCollection allFilters orders limitValue
    case result of
      Left _ -> pure []
      Right fieldMaps -> pure (rights (map fieldsToKnowledge fieldMaps))

  persist knowledge = FirestoreFailureKnowledgeRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportUpsertDocument} = environment.firestoreEnv.firestoreExecute
        FailureKnowledgeIdentifier persistUlid = knowledge.identifier
        documentId = DocumentId (Text.pack (show persistUlid))
        fieldMap = knowledgeToFields knowledge
    _result <- liftIO $ transportUpsertDocument failureKnowledgeCollection documentId fieldMap
    pure ()
