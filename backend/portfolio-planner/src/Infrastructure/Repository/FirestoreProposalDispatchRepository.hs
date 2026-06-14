{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'ProposalDispatchRepository'.

Must-03: FirestoreProposalDispatchRepositoryT newtype wrapping ReaderT.
Must-03: All 3 methods (findProposalDispatch, persistProposalDispatch, terminateProposalDispatch)
         with withRetry on persist.
Must-03: Collection = proposal_dispatches, documentId = identifier.value (ULID string).
-}
module Infrastructure.Repository.FirestoreProposalDispatchRepository (
  -- * Environment
  FirestoreProposalDispatchEnv (..),

  -- * Monad transformer
  FirestoreProposalDispatchRepositoryT (..),
  runFirestoreProposalDispatchRepositoryT,

  -- * Retry predicate (exported for tests)
  isRetryableForPersist,

  -- * Codec (exported for pure round-trip tests)
  ProposalDispatchDocument (..),
  toDocument,
  documentToDispatch,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Aggregate (OrderProposalIdentifier (..))
import Domain.OrderProposal.Ports (ProposalDispatchRepository (..))
import Domain.OrderProposal.ProposalDispatch (
  DispatchStatus (..),
  ProposalDispatch,
  ProposalDispatchIdentifier (..),
  completeDispatch,
  failDispatch,
  startDispatch,
 )
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
 )
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
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreProposalDispatchEnv = FirestoreProposalDispatchEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreProposalDispatchRepositoryT m a = FirestoreProposalDispatchRepositoryT
  { unFirestoreProposalDispatchRepositoryT :: ReaderT FirestoreProposalDispatchEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runFirestoreProposalDispatchRepositoryT ::
  FirestoreProposalDispatchEnv ->
  FirestoreProposalDispatchRepositoryT m a ->
  m a
runFirestoreProposalDispatchRepositoryT environment action =
  runReaderT (unFirestoreProposalDispatchRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

proposalDispatchesCollection :: CollectionName
proposalDispatchesCollection = CollectionName "proposal_dispatches"

-- ---------------------------------------------------------------------------
-- Firestore document codec
-- ---------------------------------------------------------------------------

data ProposalDispatchDocument = ProposalDispatchDocument
  { identifier :: ULID
  , dispatchStatus :: Text
  , orderCount :: Maybe Int64
  , orders :: Text
  , reasonCode :: Maybe Text
  , trace :: ULID
  , processedAt :: Maybe UTCTime
  }

instance ToFirestore ProposalDispatchDocument where
  toFirestoreFields document =
    HashMap.fromList $
      [ ("identifier", toValue document.identifier)
      , ("dispatchStatus", toValue document.dispatchStatus)
      , ("orders", toValue document.orders)
      , ("trace", toValue document.trace)
      ]
        <> maybe [] (\count -> [("orderCount", toValue count)]) document.orderCount
        <> maybe [] (\code -> [("reasonCode", toValue code)]) document.reasonCode
        <> maybe [] (\time -> [("processedAt", toValue time)]) document.processedAt

instance FromFirestore ProposalDispatchDocument where
  fromFirestoreFields fields = do
    identifierValue <- requireField "identifier" fields
    dispatchStatusValue <- requireField "dispatchStatus" fields
    orderCountValue <- optionalField "orderCount" fields
    ordersValue <- requireField "orders" fields
    reasonCodeValue <- optionalField "reasonCode" fields
    traceValue <- requireField "trace" fields
    processedAtValue <- optionalField "processedAt" fields
    Right
      ProposalDispatchDocument
        { identifier = identifierValue
        , dispatchStatus = dispatchStatusValue
        , orderCount = orderCountValue
        , orders = ordersValue
        , reasonCode = reasonCodeValue
        , trace = traceValue
        , processedAt = processedAtValue
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
dispatchStatusToText Completed = "completed"
dispatchStatusToText Failed = "failed"

dispatchStatusFromText :: Text -> Either Text DispatchStatus
dispatchStatusFromText "pending" = Right Pending
dispatchStatusFromText "completed" = Right Completed
dispatchStatusFromText "failed" = Right Failed
dispatchStatusFromText other = Left ("unknown dispatchStatus: " <> other)

-- | Serialize [OrderProposalIdentifier] as comma-separated ULID strings.
ordersToText :: [OrderProposalIdentifier] -> Text
ordersToText [] = ""
ordersToText identifiers = Text.intercalate "," (map (Text.pack . show . (.value)) identifiers)

-- | Deserialize comma-separated ULID strings back to [OrderProposalIdentifier].
ordersFromText :: Text -> Either Text [OrderProposalIdentifier]
ordersFromText text
  | Text.null text = Right []
  | otherwise =
      let parts = Text.splitOn "," text
       in mapM parseIdentifier parts
 where
  parseIdentifier part =
    case readMaybe (Text.unpack part) of
      Nothing -> Left ("invalid ULID in orders: " <> part)
      Just ulid -> Right OrderProposalIdentifier{value = ulid}

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

toDocument :: UTCTime -> ProposalDispatch -> ProposalDispatchDocument
toDocument _now dispatch =
  let orderCountInt64 = fmap (fromIntegral :: Int -> Int64) dispatch.orderCount
   in ProposalDispatchDocument
        { identifier = dispatch.identifier.value
        , dispatchStatus = dispatchStatusToText dispatch.dispatchStatus
        , orderCount = orderCountInt64
        , orders = ordersToText dispatch.orders
        , reasonCode = fmap reasonCodeToWire dispatch.reasonCode
        , trace = dispatch.trace.value
        , processedAt = dispatch.processedAt
        }

documentToDispatch :: ProposalDispatchDocument -> Either Text ProposalDispatch
documentToDispatch document = do
  _ <- dispatchStatusFromText document.dispatchStatus
  let dispatchIdentifier = ProposalDispatchIdentifier{value = document.identifier}
      traceValue = Trace{value = document.trace}
      (baseDispatch, _) = startDispatch dispatchIdentifier defaultSignalSnapshot traceValue
  case document.dispatchStatus of
    "pending" -> Right baseDispatch
    "completed" -> do
      orderIdentifiers <- ordersFromText document.orders
      let count = maybe (length orderIdentifiers) fromIntegral document.orderCount
      processedTime <- maybe (Left "completed dispatch missing processedAt") Right document.processedAt
      case completeDispatch count orderIdentifiers processedTime baseDispatch of
        Left domainError -> Left (Text.pack (show domainError))
        Right (dispatch, _) -> Right dispatch
    "failed" -> do
      reasonCode <- case document.reasonCode of
        Nothing -> Right Nothing
        Just codeText -> fmap Just (reasonCodeFromWire codeText)
      processedTime <- maybe (Left "failed dispatch missing processedAt") Right document.processedAt
      case failDispatch reasonCode processedTime baseDispatch of
        Left domainError -> Left (Text.pack (show domainError))
        Right (dispatch, _) -> Right dispatch
    other -> Left ("unknown dispatchStatus: " <> other)

-- ---------------------------------------------------------------------------
-- ProposalDispatchRepository instance
-- ---------------------------------------------------------------------------

instance ProposalDispatchRepository (FirestoreProposalDispatchRepositoryT IO) where
  findProposalDispatch dispatchIdentifier = FirestoreProposalDispatchRepositoryT $ do
    environment <- ask
    result <-
      liftIO $
        getDocument @ProposalDispatchDocument
          environment.firestoreContext
          proposalDispatchesCollection
          (DocumentId (Text.pack (show dispatchIdentifier.value)))
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just document) ->
        pure $ case documentToDispatch document of
          Left _ -> Nothing
          Right dispatch -> Just dispatch

  persistProposalDispatch dispatch = FirestoreProposalDispatchRepositoryT $ do
    environment <- ask
    now <- liftIO getCurrentTime
    let document = toDocument now dispatch
        documentIdentifier = DocumentId (Text.pack (show dispatch.identifier.value))
    _ <-
      liftIO $
        withRetry defaultRetryPolicyConfig isRetryableForPersist $
          upsertDocument environment.firestoreContext proposalDispatchesCollection documentIdentifier document
    pure ()

  terminateProposalDispatch dispatchIdentifier = FirestoreProposalDispatchRepositoryT $ do
    environment <- ask
    _ <-
      liftIO $
        deleteDocument
          environment.firestoreContext
          proposalDispatchesCollection
          (DocumentId (Text.pack (show dispatchIdentifier.value)))
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
