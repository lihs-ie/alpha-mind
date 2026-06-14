{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'IdempotencyKeyRepository'.

Must-11: FirestoreIdempotencyKeyRepositoryT newtype wrapping ReaderT.
Must-12: FirestoreIdempotencyKeyEnv holds firestoreContext.
Must-13: find checks idempotency_keys/{service}:{key}; processedAt = Just _ → True.
Must-14: persist upserts with processedAt = Just now, expiresAt = now + 30 days.
Must-15: terminate deletes the document.

Collection: idempotency_keys
Document ID: {service}:{eventKey}

Re-uses 'Persistence.Idempotency.IdempotencyRecord' codec but adapts
the text-key port interface (Text, Text) → m Bool directly via Firestore.
-}
module Infrastructure.Repository.FirestoreIdempotencyKeyRepository (
  -- * Environment
  FirestoreIdempotencyKeyEnv (..),

  -- * Monad transformer
  FirestoreIdempotencyKeyRepositoryT (..),
  runFirestoreIdempotencyKeyRepositoryT,

  -- * Codec (exported for TST-INFRA-008)
  IdempotencyProcessedRecord (..),

  -- * Pure helper (exported for TST-INFRA-008)
  isAlreadyProcessed,
) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Data.Time (UTCTime, addUTCTime, getCurrentTime, nominalDay)
import Domain.RiskAssessment.Port.IdempotencyKeyRepository (IdempotencyKeyRepository (..))
import Gogol.FireStore qualified as GogolFireStore
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext,
  FromFirestore (..),
  FromFirestoreValue (..),
  ToFirestore (..),
  ToFirestoreValue (..),
  deleteDocument,
  getDocument,
  upsertDocument,
 )

-- ---------------------------------------------------------------------------
-- Environment (Must-12)
-- ---------------------------------------------------------------------------

newtype FirestoreIdempotencyKeyEnv = FirestoreIdempotencyKeyEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer (Must-11)
-- ---------------------------------------------------------------------------

newtype FirestoreIdempotencyKeyRepositoryT m a = FirestoreIdempotencyKeyRepositoryT
  { unFirestoreIdempotencyKeyRepositoryT :: ReaderT FirestoreIdempotencyKeyEnv m a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO)

runFirestoreIdempotencyKeyRepositoryT ::
  FirestoreIdempotencyKeyEnv ->
  FirestoreIdempotencyKeyRepositoryT m a ->
  m a
runFirestoreIdempotencyKeyRepositoryT environment action =
  runReaderT (unFirestoreIdempotencyKeyRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

idempotencyKeysCollection :: CollectionName
idempotencyKeysCollection = CollectionName "idempotency_keys"

mkDocumentId :: Text -> Text -> DocumentId
mkDocumentId serviceText eventKeyText =
  DocumentId (serviceText <> ":" <> eventKeyText)

-- ---------------------------------------------------------------------------
-- Idempotency record codec
-- ---------------------------------------------------------------------------

-- | Minimal read-side record for existence check.
newtype IdempotencyProcessedRecord = IdempotencyProcessedRecord
  { processedAt :: Maybe UTCTime
  }

instance FromFirestore IdempotencyProcessedRecord where
  fromFirestoreFields fields = do
    processedAtValue <- optionalField "processedAt" fields
    Right IdempotencyProcessedRecord{processedAt = processedAtValue}

-- | Write-side record for persist.
data IdempotencyWriteRecord = IdempotencyWriteRecord
  { key :: Text
  , service :: Text
  , processedAt :: UTCTime
  , expiresAt :: UTCTime
  , updatedAt :: UTCTime
  }

instance ToFirestore IdempotencyWriteRecord where
  toFirestoreFields record =
    HashMap.fromList
      [ ("key", toValue record.key)
      , ("service", toValue record.service)
      , ("processedAt", toValue record.processedAt)
      , ("expiresAt", toValue record.expiresAt)
      , ("updatedAt", toValue record.updatedAt)
      ]

-- ---------------------------------------------------------------------------
-- Optional field helper
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Pure helper (TST-INFRA-008)
-- ---------------------------------------------------------------------------

{- | Determine if an idempotency record represents a processed event.

'True' when 'processedAt' is 'Just _', 'False' when 'Nothing' or absent.
Exported for pure unit test TST-INFRA-008.
-}
isAlreadyProcessed :: Maybe IdempotencyProcessedRecord -> Bool
isAlreadyProcessed Nothing = False
isAlreadyProcessed (Just record) = case record.processedAt of
  Just _ -> True
  Nothing -> False

-- ---------------------------------------------------------------------------
-- IdempotencyKeyRepository instance (Must-13/14/15)
-- ---------------------------------------------------------------------------

instance IdempotencyKeyRepository (FirestoreIdempotencyKeyRepositoryT IO) where
  -- Must-13: return True if processedAt is Just _
  find serviceText eventKeyText = FirestoreIdempotencyKeyRepositoryT $ do
    environment <- ask
    let documentId = mkDocumentId serviceText eventKeyText
    result <-
      liftIO $
        getDocument @IdempotencyProcessedRecord
          environment.firestoreContext
          idempotencyKeysCollection
          documentId
    case result of
      Left _ -> pure False
      Right maybeRecord -> pure (isAlreadyProcessed maybeRecord)

  -- Must-14: upsert with processedAt = Just now
  persist serviceText eventKeyText = FirestoreIdempotencyKeyRepositoryT $ do
    environment <- ask
    now <- liftIO getCurrentTime
    let documentId = mkDocumentId serviceText eventKeyText
        record =
          IdempotencyWriteRecord
            { key = serviceText <> ":" <> eventKeyText
            , service = serviceText
            , processedAt = now
            , expiresAt = addUTCTime (30 * nominalDay) now
            , updatedAt = now
            }
    _ <-
      liftIO $
        upsertDocument
          environment.firestoreContext
          idempotencyKeysCollection
          documentId
          record
    pure ()

  -- Must-15: delete document
  terminate serviceText eventKeyText = FirestoreIdempotencyKeyRepositoryT $ do
    environment <- ask
    let documentId = mkDocumentId serviceText eventKeyText
    _ <-
      liftIO $
        deleteDocument
          environment.firestoreContext
          idempotencyKeysCollection
          documentId
    pure ()
