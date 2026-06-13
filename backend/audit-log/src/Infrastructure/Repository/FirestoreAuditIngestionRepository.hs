{-# LANGUAGE OverloadedRecordDot #-}
{-# OPTIONS_GHC -fno-hpc #-}

{- | Firestore implementation of 'AuditIngestionRepository'.

Must-2: Delegates to common Persistence.Idempotency (reserveIdempotency /
        completeIdempotency). Document key = "audit-log:{identifier}".
Must-5: expiresAt = now + 30 days is handled by reserveIdempotency.
Must-10: idempotency_keys fields match the schema definition.
-}
module Infrastructure.Repository.FirestoreAuditIngestionRepository (
  -- * Environment
  FirestoreAuditIngestionEnv (..),

  -- * Monad transformer
  FirestoreAuditIngestionT (..),
  runFirestoreAuditIngestionT,

  -- * DocumentId generation (exported for unit tests — Must-2)
  auditIngestionDocumentKey,
) where

import Control.Monad (void)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.ULID (ULID)
import Domain.AuditLog (Trace (..))
import Domain.AuditLog.AuditIngestion (
  AuditIngestion,
  AuditIngestionIdentifier (..),
  AuditIngestionRepository (..),
  startIngestion,
 )
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext,
  deleteDocument,
  getDocument,
 )
import Persistence.Idempotency (
  IdempotencyRecord (..),
  completeIdempotency,
  reserveIdempotency,
 )

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreAuditIngestionEnv = FirestoreAuditIngestionEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreAuditIngestionT m a = FirestoreAuditIngestionT
  { unFirestoreAuditIngestionT :: ReaderT FirestoreAuditIngestionEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runFirestoreAuditIngestionT :: FirestoreAuditIngestionEnv -> FirestoreAuditIngestionT m a -> m a
runFirestoreAuditIngestionT environment action =
  runReaderT (unFirestoreAuditIngestionT action) environment

-- ---------------------------------------------------------------------------
-- Service name constant (Must-2: "audit-log:{identifier}" key format)
-- ---------------------------------------------------------------------------

auditLogServiceName :: Text
auditLogServiceName = "audit-log"

idempotencyKeysCollection :: CollectionName
idempotencyKeysCollection = CollectionName "idempotency_keys"

{- | Build the Firestore document key for an idempotency record.

 Must-2: The key format is @audit-log:{identifier}@ where @identifier@
 is the ULID string representation of the 'AuditIngestionIdentifier'.
-}
auditIngestionDocumentKey :: ULID -> Text
auditIngestionDocumentKey identifier =
  auditLogServiceName <> ":" <> Text.pack (show identifier)

-- ---------------------------------------------------------------------------
-- AuditIngestionRepository instance
-- Must-2: Delegates to reserveIdempotency / completeIdempotency.
-- ---------------------------------------------------------------------------

instance AuditIngestionRepository (FirestoreAuditIngestionT IO) where
  find ingestionIdentifier = FirestoreAuditIngestionT $ do
    environment <- ask
    let documentKey = auditIngestionDocumentKey ingestionIdentifier.value
    result <-
      liftIO $
        getDocument @IdempotencyRecord
          environment.firestoreContext
          idempotencyKeysCollection
          (DocumentId documentKey)
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just record) -> pure (Just (idempotencyRecordToIngestion record))

  -- Must-2: Uses reserveIdempotency to write to idempotency_keys.
  -- Must-5: TTL 30 days is set inside reserveIdempotency.
  persist ingestion = FirestoreAuditIngestionT $ do
    environment <- ask
    _ <-
      liftIO $
        reserveIdempotency
          environment.firestoreContext
          auditLogServiceName
          ingestion.identifier.value
          ingestion.trace.value
    -- If already reserved and processed, complete it.
    case ingestion.processedAt of
      Just _ ->
        liftIO $
          void
            ( completeIdempotency
                environment.firestoreContext
                auditLogServiceName
                ingestion.identifier.value
            )
      Nothing -> pure ()

  terminate ingestionIdentifier = FirestoreAuditIngestionT $ do
    environment <- ask
    let documentKey = auditIngestionDocumentKey ingestionIdentifier.value
    _ <-
      liftIO $
        deleteDocument
          environment.firestoreContext
          idempotencyKeysCollection
          (DocumentId documentKey)
    pure ()

-- ---------------------------------------------------------------------------
-- Codec helper
-- ---------------------------------------------------------------------------

idempotencyRecordToIngestion :: IdempotencyRecord -> AuditIngestion
idempotencyRecordToIngestion record =
  let traceValue = Trace{value = record.trace}
      ingestionIdentifier = AuditIngestionIdentifier{value = record.identifier}
      base = startIngestion ingestionIdentifier traceValue
   in base
