{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'IdempotencyKeyRepository'.

Must-04: FirestoreIdempotencyRepositoryT newtype wrapping ReaderT.
Must-04: All 3 methods (findIdempotencyKey, persistIdempotencyKey, terminateIdempotencyKey)
         with withRetry on persist.
Must-04: Collection = idempotency_keys, documentId = "portfolio-planner:{identifier.value}".
         Fields: identifier, service="portfolio-planner", processedAt, trace.
-}
module Infrastructure.Repository.FirestoreIdempotencyRepository (
  -- * Environment
  FirestoreIdempotencyEnv (..),

  -- * Monad transformer
  FirestoreIdempotencyRepositoryT (..),
  runFirestoreIdempotencyRepositoryT,

  -- * Retry predicate (exported for tests)
  isRetryableForPersist,

  -- * Document id helper (exported for tests)
  idempotencyDocumentId,

  -- * Codec (exported for pure round-trip tests)
  IdempotencyDocument (..),
  toDocument,
  documentToDispatch,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Ports (IdempotencyKeyRepository (..))
import Domain.OrderProposal.ProposalDispatch (
  ProposalDispatch,
  ProposalDispatchIdentifier (..),
  startDispatch,
 )
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
 )
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext,
  FirestoreError (..),
  FromFirestore (..),
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

newtype FirestoreIdempotencyEnv = FirestoreIdempotencyEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreIdempotencyRepositoryT m a = FirestoreIdempotencyRepositoryT
  { unFirestoreIdempotencyRepositoryT :: ReaderT FirestoreIdempotencyEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runFirestoreIdempotencyRepositoryT ::
  FirestoreIdempotencyEnv ->
  FirestoreIdempotencyRepositoryT m a ->
  m a
runFirestoreIdempotencyRepositoryT environment action =
  runReaderT (unFirestoreIdempotencyRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

idempotencyKeysCollection :: CollectionName
idempotencyKeysCollection = CollectionName "idempotency_keys"

-- ---------------------------------------------------------------------------
-- Document id builder
-- ---------------------------------------------------------------------------

{- | Build the Firestore document id for an idempotency key.
Format: "portfolio-planner:{ulid-string}" per Must-04.
-}
idempotencyDocumentId :: ProposalDispatchIdentifier -> DocumentId
idempotencyDocumentId dispatchIdentifier =
  let ulidText = Text.pack (show dispatchIdentifier.value)
   in DocumentId ("portfolio-planner:" <> ulidText)

-- ---------------------------------------------------------------------------
-- Firestore document codec
-- ---------------------------------------------------------------------------

data IdempotencyDocument = IdempotencyDocument
  { identifier :: ULID
  , service :: Text
  , processedAt :: UTCTime
  , trace :: ULID
  }

instance ToFirestore IdempotencyDocument where
  toFirestoreFields document =
    HashMap.fromList
      [ ("identifier", toValue document.identifier)
      , ("service", toValue document.service)
      , ("processedAt", toValue document.processedAt)
      , ("trace", toValue document.trace)
      ]

instance FromFirestore IdempotencyDocument where
  fromFirestoreFields fields = do
    identifierValue <- requireField "identifier" fields
    serviceValue <- requireField "service" fields
    processedAtValue <- requireField "processedAt" fields
    traceValue <- requireField "trace" fields
    Right
      IdempotencyDocument
        { identifier = identifierValue
        , service = serviceValue
        , processedAt = processedAtValue
        , trace = traceValue
        }

-- ---------------------------------------------------------------------------
-- Codec helpers
-- ---------------------------------------------------------------------------

-- | Build a default SignalSnapshot for ProposalDispatch reconstruction.
defaultSignalSnapshot :: SignalSnapshot
defaultSignalSnapshot =
  SignalSnapshot
    { signalVersion = ""
    , modelVersion = ""
    , featureVersion = ""
    , storagePath = ""
    , degradationFlag = Normal
    , requiresComplianceReview = False
    }

toDocument :: UTCTime -> ProposalDispatch -> IdempotencyDocument
toDocument now dispatch =
  IdempotencyDocument
    { identifier = dispatch.identifier.value
    , service = "portfolio-planner"
    , processedAt = now
    , trace = dispatch.trace.value
    }

documentToDispatch :: IdempotencyDocument -> Either Text ProposalDispatch
documentToDispatch document =
  let dispatchIdentifier = ProposalDispatchIdentifier{value = document.identifier}
      traceValue = Trace{value = document.trace}
      (baseDispatch, _) = startDispatch dispatchIdentifier defaultSignalSnapshot traceValue
   in Right baseDispatch

-- ---------------------------------------------------------------------------
-- IdempotencyKeyRepository instance
-- ---------------------------------------------------------------------------

instance IdempotencyKeyRepository (FirestoreIdempotencyRepositoryT IO) where
  findIdempotencyKey dispatchIdentifier = FirestoreIdempotencyRepositoryT $ do
    environment <- ask
    let documentIdentifier = idempotencyDocumentId dispatchIdentifier
    result <-
      liftIO $
        getDocument @IdempotencyDocument
          environment.firestoreContext
          idempotencyKeysCollection
          documentIdentifier
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just document) ->
        pure $ case documentToDispatch document of
          Left _ -> Nothing
          Right dispatch -> Just dispatch

  persistIdempotencyKey dispatch = FirestoreIdempotencyRepositoryT $ do
    environment <- ask
    now <- liftIO getCurrentTime
    let document = toDocument now dispatch
        documentIdentifier = idempotencyDocumentId dispatch.identifier
    _ <-
      liftIO $
        withRetry defaultRetryPolicyConfig isRetryableForPersist $
          upsertDocument environment.firestoreContext idempotencyKeysCollection documentIdentifier document
    pure ()

  terminateIdempotencyKey dispatchIdentifier = FirestoreIdempotencyRepositoryT $ do
    environment <- ask
    let documentIdentifier = idempotencyDocumentId dispatchIdentifier
    _ <-
      liftIO $
        deleteDocument
          environment.firestoreContext
          idempotencyKeysCollection
          documentIdentifier
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
