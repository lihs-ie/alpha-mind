{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'OrderExecutionRepository'.

Must-10: FirestoreOrderExecutionRepositoryT newtype wrapping ReaderT.
Must-11: All 5 methods (find, findByStatus, search, persist, terminate) with withRetry on persist.
Must-12: Collection = order_executions, documentId = identifier.value (ULID string).
Must-13: FirestoreOrderExecutionEnv holds firestoreContext; isRetryableForPersist defined.
-}
module Infrastructure.Repository.FirestoreOrderExecutionRepository (
  -- * Environment
  FirestoreOrderExecutionEnv (..),

  -- * Monad transformer
  FirestoreOrderExecutionRepositoryT (..),
  runFirestoreOrderExecutionRepositoryT,

  -- * Retry predicate (exported for tests)
  isRetryableForPersist,

  -- * Codec (exported for pure round-trip tests)
  OrderExecutionDocument (..),
  toDocument,
  documentToExecution,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.Int (Int64)
import Data.Maybe (catMaybes, fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.Aggregate (
  ExecutionRequest (..),
  ExecutionSearchCriteria (..),
  ExecutionStatus (..),
  OrderExecution,
  OrderExecutionIdentifier (..),
  OrderExecutionRepository (..),
  acceptApprovedOrder,
  recordBrokerFailure,
  recordBrokerSuccess,
 )
import Domain.OrderExecution.ReasonCode (ReasonCode (..))
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

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreOrderExecutionEnv = FirestoreOrderExecutionEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreOrderExecutionRepositoryT m a = FirestoreOrderExecutionRepositoryT
  { unFirestoreOrderExecutionRepositoryT :: ReaderT FirestoreOrderExecutionEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runFirestoreOrderExecutionRepositoryT ::
  FirestoreOrderExecutionEnv ->
  FirestoreOrderExecutionRepositoryT m a ->
  m a
runFirestoreOrderExecutionRepositoryT environment action =
  runReaderT (unFirestoreOrderExecutionRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

orderExecutionsCollection :: CollectionName
orderExecutionsCollection = CollectionName "order_executions"

-- ---------------------------------------------------------------------------
-- Firestore document codec
-- ---------------------------------------------------------------------------

data OrderExecutionDocument = OrderExecutionDocument
  { identifier :: ULID
  , status :: Text
  , attemptCount :: Int64
  , brokerOrder :: Maybe Text
  , reasonCode :: Maybe Text
  , trace :: ULID
  , executedAt :: Maybe UTCTime
  , updatedAt :: UTCTime
  , version :: Int64
  }

instance ToFirestore OrderExecutionDocument where
  toFirestoreFields document =
    HashMap.fromList $
      [ ("identifier", toValue document.identifier)
      , ("status", toValue document.status)
      , ("attemptCount", toValue document.attemptCount)
      , ("trace", toValue document.trace)
      , ("updatedAt", toValue document.updatedAt)
      , ("version", toValue document.version)
      ]
        <> maybe [] (\bo -> [("brokerOrder", toValue bo)]) document.brokerOrder
        <> maybe [] (\rc -> [("reasonCode", toValue rc)]) document.reasonCode
        <> maybe [] (\ea -> [("executedAt", toValue ea)]) document.executedAt

instance FromFirestore OrderExecutionDocument where
  fromFirestoreFields fields = do
    identifierValue <- requireField "identifier" fields
    statusValue <- requireField "status" fields
    attemptCountValue <- requireField "attemptCount" fields
    brokerOrderValue <- optionalField "brokerOrder" fields
    reasonCodeValue <- optionalField "reasonCode" fields
    traceValue <- requireField "trace" fields
    executedAtValue <- optionalField "executedAt" fields
    updatedAtValue <- requireField "updatedAt" fields
    versionValue <- requireField "version" fields
    Right
      OrderExecutionDocument
        { identifier = identifierValue
        , status = statusValue
        , attemptCount = attemptCountValue
        , brokerOrder = brokerOrderValue
        , reasonCode = reasonCodeValue
        , trace = traceValue
        , executedAt = executedAtValue
        , updatedAt = updatedAtValue
        , version = versionValue
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

executionStatusToText :: ExecutionStatus -> Text
executionStatusToText Approved = "APPROVED"
executionStatusToText Executed = "EXECUTED"
executionStatusToText Failed = "FAILED"

executionStatusFromText :: Text -> Either Text ExecutionStatus
executionStatusFromText "APPROVED" = Right Approved
executionStatusFromText "EXECUTED" = Right Executed
executionStatusFromText "FAILED" = Right Failed
executionStatusFromText other = Left ("unknown executionStatus: " <> other)

reasonCodeFromText :: Text -> Either Text ReasonCode
reasonCodeFromText "EXECUTION_BROKER_TIMEOUT" = Right ExecutionBrokerTimeout
reasonCodeFromText "EXECUTION_BROKER_REJECTED" = Right ExecutionBrokerRejected
reasonCodeFromText "EXECUTION_MARKET_CLOSED" = Right ExecutionMarketClosed
reasonCodeFromText "EXECUTION_INSUFFICIENT_FUNDS" = Right ExecutionInsufficientFunds
reasonCodeFromText "IDEMPOTENCY_DUPLICATE_EVENT" = Right IdempotencyDuplicateEvent
reasonCodeFromText "STATE_CONFLICT" = Right StateConflict
reasonCodeFromText "DEPENDENCY_TIMEOUT" = Right DependencyTimeout
reasonCodeFromText "INTERNAL_ERROR" = Right InternalError
reasonCodeFromText other = Left ("unknown reasonCode: " <> other)

toDocument :: UTCTime -> OrderExecution -> OrderExecutionDocument
toDocument now execution =
  let statusText = executionStatusToText execution.status
      traceUlid = execution.trace.value
      attemptCountInt64 = fromIntegral execution.attemptCount
   in OrderExecutionDocument
        { identifier = execution.identifier.value
        , status = statusText
        , attemptCount = attemptCountInt64
        , brokerOrder = execution.brokerOrder
        , reasonCode = fmap reasonCodeToWire execution.reasonCode
        , trace = traceUlid
        , executedAt = execution.executedAt
        , updatedAt = now
        , version = 1
        }

documentToExecution :: OrderExecutionDocument -> Either Text OrderExecution
documentToExecution document = do
  executionStatus <- executionStatusFromText document.status
  let executionIdentifier = OrderExecutionIdentifier{value = document.identifier}
      traceValue = Trace{value = document.trace}
      -- Reconstruct a minimal ExecutionRequest (not stored in Firestore — use placeholder)
      executionRequest = ExecutionRequest{symbol = "", side = "", qty = 0}
      (baseExecution, _) = acceptApprovedOrder executionIdentifier executionRequest traceValue
  case executionStatus of
    Approved -> Right baseExecution
    Executed ->
      case document.brokerOrder of
        Nothing -> Left "executed document missing brokerOrder"
        Just brokerOrderIdentifier ->
          case document.executedAt of
            Nothing -> Left "executed document missing executedAt"
            Just executedAtTime ->
              case recordBrokerSuccess brokerOrderIdentifier executedAtTime baseExecution of
                Left domainError -> Left (Text.pack (show domainError))
                Right (execution, _) -> Right execution
    Failed -> do
      reasonCode <- case document.reasonCode of
        Nothing -> Right DependencyTimeout
        Just rcText -> reasonCodeFromText rcText
      case recordBrokerFailure reasonCode Nothing document.updatedAt baseExecution of
        Left domainError -> Left (Text.pack (show domainError))
        Right (execution, _) -> Right execution

-- ---------------------------------------------------------------------------
-- OrderExecutionRepository instance
-- ---------------------------------------------------------------------------

instance OrderExecutionRepository (FirestoreOrderExecutionRepositoryT IO) where
  findExecution executionIdentifier = FirestoreOrderExecutionRepositoryT $ do
    environment <- ask
    result <-
      liftIO $
        getDocument @OrderExecutionDocument
          environment.firestoreContext
          orderExecutionsCollection
          (DocumentId (Text.pack (show executionIdentifier.value)))
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just document) ->
        pure $ case documentToExecution document of
          Left _ -> Nothing
          Right execution -> Just execution

  findExecutionsByStatus executionStatus = FirestoreOrderExecutionRepositoryT $ do
    environment <- ask
    result <-
      liftIO $
        runQuery @OrderExecutionDocument
          environment.firestoreContext
          orderExecutionsCollection
          [QueryFilterEqual{filterField = "status", filterValue = toValue (executionStatusToText executionStatus)}]
          [QueryOrder{orderField = "updatedAt", orderDirection = Descending}]
          100
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (concatMap toMaybeExecution documents)

  searchExecutions criteria = FirestoreOrderExecutionRepositoryT $ do
    environment <- ask
    let filters =
          catMaybes
            [ fmap
                ( \s ->
                    QueryFilterEqual
                      { filterField = "status"
                      , filterValue = toValue (executionStatusToText s)
                      }
                )
                criteria.statusFilter
            ]
        orders = [QueryOrder{orderField = "updatedAt", orderDirection = Descending}]
        limitCount = fromMaybe 50 criteria.limitCount
    result <-
      liftIO $
        runQuery @OrderExecutionDocument
          environment.firestoreContext
          orderExecutionsCollection
          filters
          orders
          limitCount
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (concatMap toMaybeExecution documents)

  persistExecution execution = FirestoreOrderExecutionRepositoryT $ do
    environment <- ask
    now <- liftIO getCurrentTime
    let document = toDocument now execution
        documentIdentifier = DocumentId (Text.pack (show execution.identifier.value))
    _ <-
      liftIO $
        withRetry defaultRetryPolicyConfig isRetryableForPersist $
          upsertDocument environment.firestoreContext orderExecutionsCollection documentIdentifier document
    pure ()

  terminateExecution executionIdentifier = FirestoreOrderExecutionRepositoryT $ do
    environment <- ask
    _ <-
      liftIO $
        deleteDocument
          environment.firestoreContext
          orderExecutionsCollection
          (DocumentId (Text.pack (show executionIdentifier.value)))
    pure ()

-- ---------------------------------------------------------------------------
-- Retry predicate
-- ---------------------------------------------------------------------------

{- | FirestoreErrorDecode is NOT retryable (data schema invalid).
Transport and 5xx/429 errors are retryable.
-}
isRetryableForPersist :: FirestoreError -> Bool
isRetryableForPersist (FirestoreErrorDecode _) = False
isRetryableForPersist other = isRetryableError other
 where
  isRetryableError (FirestoreErrorTransport _) = True
  isRetryableError (FirestoreErrorUnexpected httpStatus _) = httpStatus == 429 || httpStatus >= 500
  isRetryableError _ = False

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

toMaybeExecution :: OrderExecutionDocument -> [OrderExecution]
toMaybeExecution document =
  case documentToExecution document of
    Left _ -> []
    Right execution -> [execution]
