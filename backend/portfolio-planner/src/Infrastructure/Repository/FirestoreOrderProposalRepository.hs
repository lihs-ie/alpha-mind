{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'OrderProposalRepository'.

Must-02: FirestoreOrderProposalRepositoryT newtype wrapping ReaderT.
Must-02: All 5 methods (findOrderProposal, findOrderProposalsByStatus, searchOrderProposals,
         persistOrderProposal, terminateOrderProposal) with withRetry on persist.
Must-02: Collection = orders, documentId = identifier.value (ULID string).
-}
module Infrastructure.Repository.FirestoreOrderProposalRepository (
  -- * Environment
  FirestoreOrderProposalEnv (..),

  -- * Monad transformer
  FirestoreOrderProposalRepositoryT (..),
  runFirestoreOrderProposalRepositoryT,

  -- * Retry predicate (exported for tests)
  isRetryableForPersist,

  -- * Codec (exported for pure round-trip tests)
  OrderProposalDocument (..),
  toDocument,
  documentToProposal,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.HashMap.Strict qualified as HashMap
import Data.Maybe (catMaybes, fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Aggregate (
  OrderProposal,
  OrderProposalIdentifier (..),
  OrderProposalSearchCriteria (..),
  OrderStatus (..),
  Side (..),
  createProposal,
 )
import Domain.OrderProposal.Ports (OrderProposalRepository (..))
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
  StrategySnapshot (..),
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
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreOrderProposalEnv = FirestoreOrderProposalEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreOrderProposalRepositoryT m a = FirestoreOrderProposalRepositoryT
  { unFirestoreOrderProposalRepositoryT :: ReaderT FirestoreOrderProposalEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runFirestoreOrderProposalRepositoryT ::
  FirestoreOrderProposalEnv ->
  FirestoreOrderProposalRepositoryT m a ->
  m a
runFirestoreOrderProposalRepositoryT environment action =
  runReaderT (unFirestoreOrderProposalRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

ordersCollection :: CollectionName
ordersCollection = CollectionName "orders"

-- ---------------------------------------------------------------------------
-- Firestore document codec
-- ---------------------------------------------------------------------------

data OrderProposalDocument = OrderProposalDocument
  { identifier :: ULID
  , symbol :: Text
  , side :: Text
  , qty :: Text
  , status :: Text
  , trace :: ULID
  , createdAt :: UTCTime
  }

instance ToFirestore OrderProposalDocument where
  toFirestoreFields document =
    HashMap.fromList
      [ ("identifier", toValue document.identifier)
      , ("symbol", toValue document.symbol)
      , ("side", toValue document.side)
      , ("qty", toValue document.qty)
      , ("status", toValue document.status)
      , ("trace", toValue document.trace)
      , ("createdAt", toValue document.createdAt)
      ]

instance FromFirestore OrderProposalDocument where
  fromFirestoreFields fields = do
    identifierValue <- requireField "identifier" fields
    symbolValue <- requireField "symbol" fields
    sideValue <- requireField "side" fields
    qtyValue <- requireField "qty" fields
    statusValue <- requireField "status" fields
    traceValue <- requireField "trace" fields
    createdAtValue <- requireField "createdAt" fields
    Right
      OrderProposalDocument
        { identifier = identifierValue
        , symbol = symbolValue
        , side = sideValue
        , qty = qtyValue
        , status = statusValue
        , trace = traceValue
        , createdAt = createdAtValue
        }

-- ---------------------------------------------------------------------------
-- Codec helpers
-- ---------------------------------------------------------------------------

sideToText :: Side -> Text
sideToText Buy = "BUY"
sideToText Sell = "SELL"

sideFromText :: Text -> Either Text Side
sideFromText "BUY" = Right Buy
sideFromText "SELL" = Right Sell
sideFromText other = Left ("unknown side: " <> other)

orderStatusToText :: OrderStatus -> Text
orderStatusToText Proposed = "PROPOSED"
orderStatusToText Approved = "APPROVED"
orderStatusToText Rejected = "REJECTED"
orderStatusToText Executed = "EXECUTED"
orderStatusToText Failed = "FAILED"

orderStatusFromText :: Text -> Either Text OrderStatus
orderStatusFromText "PROPOSED" = Right Proposed
orderStatusFromText "APPROVED" = Right Approved
orderStatusFromText "REJECTED" = Right Rejected
orderStatusFromText "EXECUTED" = Right Executed
orderStatusFromText "FAILED" = Right Failed
orderStatusFromText other = Left ("unknown status: " <> other)

-- | Serialize Rational as "numerator % denominator" text.
rationalToText :: Rational -> Text
rationalToText r = Text.pack (show r)

-- | Deserialize Rational from "numerator % denominator" text.
rationalFromText :: Text -> Either Text Rational
rationalFromText text =
  case readMaybe (Text.unpack text) :: Maybe Rational of
    Nothing -> Left ("invalid rational: " <> text)
    Just r -> Right r

-- | Build a default SignalSnapshot for reconstruction (fields not stored in orders collection).
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

-- | Build a default StrategySnapshot for reconstruction.
defaultStrategySnapshot :: StrategySnapshot
defaultStrategySnapshot =
  StrategySnapshot
    { maxOrderCount = 0
    , maxSingleOrderQty = 0
    , rebalanceThreshold = 0
    }

toDocument :: UTCTime -> OrderProposal -> OrderProposalDocument
toDocument _now proposal =
  OrderProposalDocument
    { identifier = proposal.identifier.value
    , symbol = proposal.symbol
    , side = sideToText proposal.side
    , qty = rationalToText proposal.qty
    , status = orderStatusToText proposal.status
    , trace = proposal.trace.value
    , createdAt = proposal.createdAt
    }

documentToProposal :: OrderProposalDocument -> Either Text OrderProposal
documentToProposal document = do
  sideValue <- sideFromText document.side
  _statusValue <- orderStatusFromText document.status
  qtyValue <- rationalFromText document.qty
  let proposalIdentifier = OrderProposalIdentifier{value = document.identifier}
      traceValue = Trace{value = document.trace}
  case createProposal
    proposalIdentifier
    document.symbol
    sideValue
    qtyValue
    defaultSignalSnapshot
    Nothing
    defaultStrategySnapshot
    traceValue
    document.createdAt of
    Left domainError -> Left (Text.pack (show domainError))
    Right (proposal, _) -> Right proposal

-- ---------------------------------------------------------------------------
-- OrderProposalRepository instance
-- ---------------------------------------------------------------------------

instance OrderProposalRepository (FirestoreOrderProposalRepositoryT IO) where
  findOrderProposal proposalIdentifier = FirestoreOrderProposalRepositoryT $ do
    environment <- ask
    result <-
      liftIO $
        getDocument @OrderProposalDocument
          environment.firestoreContext
          ordersCollection
          (DocumentId (Text.pack (show proposalIdentifier.value)))
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just document) ->
        pure $ case documentToProposal document of
          Left _ -> Nothing
          Right proposal -> Just proposal

  findOrderProposalsByStatus status = FirestoreOrderProposalRepositoryT $ do
    environment <- ask
    result <-
      liftIO $
        runQuery @OrderProposalDocument
          environment.firestoreContext
          ordersCollection
          [QueryFilterEqual{filterField = "status", filterValue = toValue (orderStatusToText status)}]
          [QueryOrder{orderField = "createdAt", orderDirection = Descending}]
          100
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (concatMap toMaybeProposal documents)

  searchOrderProposals criteria = FirestoreOrderProposalRepositoryT $ do
    environment <- ask
    let filters =
          catMaybes
            [ fmap
                ( \s ->
                    QueryFilterEqual
                      { filterField = "status"
                      , filterValue = toValue (orderStatusToText s)
                      }
                )
                criteria.statusFilter
            ]
        orders = [QueryOrder{orderField = "createdAt", orderDirection = Descending}]
        limitCount = fromMaybe 50 criteria.limitCount
    result <-
      liftIO $
        runQuery @OrderProposalDocument
          environment.firestoreContext
          ordersCollection
          filters
          orders
          limitCount
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (concatMap toMaybeProposal documents)

  persistOrderProposal proposal = FirestoreOrderProposalRepositoryT $ do
    environment <- ask
    now <- liftIO getCurrentTime
    let document = toDocument now proposal
        documentIdentifier = DocumentId (Text.pack (show proposal.identifier.value))
    _ <-
      liftIO $
        withRetry defaultRetryPolicyConfig isRetryableForPersist $
          upsertDocument environment.firestoreContext ordersCollection documentIdentifier document
    pure ()

  terminateOrderProposal proposalIdentifier = FirestoreOrderProposalRepositoryT $ do
    environment <- ask
    _ <-
      liftIO $
        deleteDocument
          environment.firestoreContext
          ordersCollection
          (DocumentId (Text.pack (show proposalIdentifier.value)))
    pure ()

-- ---------------------------------------------------------------------------
-- Retry predicate
-- ---------------------------------------------------------------------------

{- | FirestoreErrorDecode is NOT retryable (DATA_SCHEMA_INVALID).
Transport and 5xx/429 errors are retryable.
-}
isRetryableForPersist :: FirestoreError -> Bool
isRetryableForPersist (FirestoreErrorDecode _) = False
isRetryableForPersist other = isRetryableError other
 where
  isRetryableError (FirestoreErrorTransport _) = True
  isRetryableError (FirestoreErrorUnexpected status _) = status == 429 || status >= 500
  isRetryableError _ = False

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

toMaybeProposal :: OrderProposalDocument -> [OrderProposal]
toMaybeProposal document =
  case documentToProposal document of
    Left _ -> []
    Right proposal -> [proposal]
