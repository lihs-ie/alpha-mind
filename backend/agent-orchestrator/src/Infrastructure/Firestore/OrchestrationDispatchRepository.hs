{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'OrchestrationDispatchRepository'.

Must-15: find, persist, terminate implemented via injectable FirestoreTransport.
Must-16: expiresAt = processedAt + 30 days (RFC3339 via ToFirestoreValue UTCTime).

Collection: @idempotency_keys@
Document ID: @"agent-orchestrator:{identifier.value}"@ (Must-15 service prefix convention)
-}
module Infrastructure.Firestore.OrchestrationDispatchRepository (
  -- * Environment
  FirestoreOrchestrationDispatchEnv (..),

  -- * Monad transformer
  FirestoreOrchestrationDispatchRepositoryT (..),
  runFirestoreOrchestrationDispatchRepositoryT,

  -- * Codec (exported for pure round-trip tests)
  dispatchToFields,
  fieldsToDispatch,

  -- * Document ID builder (exported for prefix tests)
  buildDispatchDocumentId,
) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.Class (MonadTrans)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.HashMap.Strict qualified as HashMap
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (NominalDiffTime, UTCTime, addUTCTime, getCurrentTime)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (UTCTime))
import Data.ULID (ULID)
import Domain.HypothesisOrchestration (Trace (..))
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.OrchestrationDispatch (
  DispatchStatus (..),
  OrchestrationDispatch,
  OrchestrationDispatchIdentifier (..),
  OrchestrationDispatchRepository (..),
  startDispatch,
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.ValueObjects (
  SourceEventType (..),
  mkSourceEventSnapshot,
 )
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.Firestore.Env (FirestoreEnv (..), FirestoreTransport (..))
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  ToFirestoreValue (..),
  requireField,
 )
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

idempotencyKeysCollection :: CollectionName
idempotencyKeysCollection = CollectionName "idempotency_keys"

-- | Must-16: 30 days in seconds.
thirtyDaysInSeconds :: NominalDiffTime
thirtyDaysInSeconds = 30 * 24 * 60 * 60

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreOrchestrationDispatchEnv = FirestoreOrchestrationDispatchEnv
  { firestoreEnv :: FirestoreEnv
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreOrchestrationDispatchRepositoryT m a = FirestoreOrchestrationDispatchRepositoryT
  { unFirestoreOrchestrationDispatchRepositoryT :: ReaderT FirestoreOrchestrationDispatchEnv m a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO, MonadTrans)

runFirestoreOrchestrationDispatchRepositoryT ::
  FirestoreOrchestrationDispatchEnv ->
  FirestoreOrchestrationDispatchRepositoryT m a ->
  m a
runFirestoreOrchestrationDispatchRepositoryT environment action =
  runReaderT (unFirestoreOrchestrationDispatchRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Document ID (Must-15: "agent-orchestrator:{ulid}")
-- ---------------------------------------------------------------------------

{- | Build the Firestore document ID for an 'OrchestrationDispatch'.
Must-15: prefix is @"agent-orchestrator:"@ per Firestore design §3.8.
Exported for prefix tests.
-}
buildDispatchDocumentId :: OrchestrationDispatchIdentifier -> DocumentId
buildDispatchDocumentId dispatchIdentifier =
  let OrchestrationDispatchIdentifier dispatchUlid = dispatchIdentifier
   in DocumentId ("agent-orchestrator:" <> Text.pack (show dispatchUlid))

-- ---------------------------------------------------------------------------
-- Status / codec helpers
-- ---------------------------------------------------------------------------

dispatchStatusToText :: DispatchStatus -> Text
dispatchStatusToText Pending = "pending"
dispatchStatusToText Published = "published"
dispatchStatusToText DispatchFailed = "failed"
dispatchStatusToText Duplicate = "duplicate"

reasonCodeToText :: ReasonCode -> Text
reasonCodeToText ResourceNotFound = "RESOURCE_NOT_FOUND"
reasonCodeToText RequestValidationFailed = "REQUEST_VALIDATION_FAILED"
reasonCodeToText StateConflict = "STATE_CONFLICT"
reasonCodeToText IdempotencyDuplicateEvent = "IDEMPOTENCY_DUPLICATE_EVENT"
reasonCodeToText DependencyTimeout = "DEPENDENCY_TIMEOUT"
reasonCodeToText DependencyUnavailable = "DEPENDENCY_UNAVAILABLE"

sourceEventTypeToText :: SourceEventType -> Text
sourceEventTypeToText InsightCollected = "insight.collected"
sourceEventTypeToText HypothesisRetestRequested = "hypothesis.retest.requested"

sourceEventTypeFromText :: Text -> Either DomainError SourceEventType
sourceEventTypeFromText "insight.collected" = Right InsightCollected
sourceEventTypeFromText "hypothesis.retest.requested" = Right HypothesisRetestRequested
sourceEventTypeFromText _other = Left (MissingRequiredFields ["sourceEventType"] RequestValidationFailed)

-- ---------------------------------------------------------------------------
-- Firestore codec
-- ---------------------------------------------------------------------------

{- | Encode an 'OrchestrationDispatch' to Firestore field map.
Must-15: fields written: identifier, service (fixed "agent-orchestrator"),
         processedAt, trace, expiresAt, updatedAt.
Must-16: expiresAt = processedAt + 30 days (UTC).
Exported for pure round-trip tests.
-}
dispatchToFields :: UTCTime -> OrchestrationDispatch -> HashMap.HashMap Text GogolFireStore.Value
dispatchToFields now dispatch =
  let processedAtValue = fromMaybe now dispatch.processedAt
      expiresAt = addUTCTime thirtyDaysInSeconds processedAtValue
      OrchestrationDispatchIdentifier dispatchUlid = dispatch.identifier
      Trace dispatchTraceUlid = dispatch.trace
   in HashMap.fromList $
        [ ("identifier", toValue (Text.pack (show dispatchUlid)))
        , ("service", toValue ("agent-orchestrator" :: Text))
        , ("trace", toValue (Text.pack (show dispatchTraceUlid)))
        , ("status", toValue (dispatchStatusToText dispatch.dispatchStatus))
        , ("sourceEventType", toValue (sourceEventTypeToText dispatch.sourceEventType))
        , ("expiresAt", toValue expiresAt)
        , ("updatedAt", toValue now)
        ]
          <> maybe [] (\t -> [("processedAt", toValue t)]) dispatch.processedAt
          <> maybe [] (\r -> [("reasonCode", toValue (reasonCodeToText r))]) dispatch.reasonCode
          <> maybe [] (\h -> [("hypothesis", toValue h)]) dispatch.hypothesis

{- | Decode a Firestore field map to an 'OrchestrationDispatch'.
Exported for pure round-trip tests.
-}
fieldsToDispatch :: HashMap.HashMap Text GogolFireStore.Value -> Either DomainError OrchestrationDispatch
fieldsToDispatch fields = do
  identifierText <- liftTextError (requireField "identifier" fields)
  identifierUlid <- case readMaybe (Text.unpack identifierText) of
    Nothing -> Left (MissingRequiredFields ["identifier"] RequestValidationFailed)
    Just ulid -> Right (ulid :: ULID)
  traceText <- liftTextError (requireField "trace" fields)
  traceUlid <- case readMaybe (Text.unpack traceText) of
    Nothing -> Left (MissingRequiredFields ["trace"] RequestValidationFailed)
    Just ulid -> Right (ulid :: ULID)
  sourceEventTypeText <- liftTextError (requireField "sourceEventType" fields)
  sourceEventTypeValue <- sourceEventTypeFromText sourceEventTypeText
  -- Build a minimal snapshot for reconstruction
  let snapshotResult =
        mkSourceEventSnapshot
          identifierText
          sourceEventTypeValue
          (UTCTime (fromGregorian 1970 1 1) 0)
          (Text.pack (show traceUlid))
          "{}"
  snapshot <- case snapshotResult of
    Left domainError -> Left domainError
    Right s -> Right s
  let baseDispatch =
        startDispatch
          OrchestrationDispatchIdentifier{value = identifierUlid}
          snapshot
          sourceEventTypeValue
          Trace{value = traceUlid}
  pure baseDispatch

liftTextError :: Either Text a -> Either DomainError a
liftTextError (Right x) = Right x
liftTextError (Left message) = Left (MissingRequiredFields [message] ResourceNotFound)

-- ---------------------------------------------------------------------------
-- OrchestrationDispatchRepository instance (Must-15)
-- ---------------------------------------------------------------------------

instance OrchestrationDispatchRepository (FirestoreOrchestrationDispatchRepositoryT IO) where
  find dispatchIdentifier = FirestoreOrchestrationDispatchRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportGetDocument} = environment.firestoreEnv.firestoreExecute
        documentId = buildDispatchDocumentId dispatchIdentifier
    result <- liftIO $ transportGetDocument idempotencyKeysCollection documentId
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just fieldMap) ->
        pure $ case fieldsToDispatch fieldMap of
          Left _ -> Nothing
          Right dispatch -> Just dispatch

  -- Must-15: persist writes identifier, service, processedAt, trace, expiresAt (Must-16), updatedAt.
  persist dispatch = FirestoreOrchestrationDispatchRepositoryT $ do
    environment <- ask
    now <- liftIO getCurrentTime
    let FirestoreTransport{transportUpsertDocument} = environment.firestoreEnv.firestoreExecute
        documentId = buildDispatchDocumentId dispatch.identifier
        fieldMap = dispatchToFields now dispatch
    _result <- liftIO $ transportUpsertDocument idempotencyKeysCollection documentId fieldMap
    pure ()

  terminate dispatchIdentifier = FirestoreOrchestrationDispatchRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportDeleteDocument} = environment.firestoreEnv.firestoreExecute
        documentId = buildDispatchDocumentId dispatchIdentifier
    _result <- liftIO $ transportDeleteDocument idempotencyKeysCollection documentId
    pure ()
