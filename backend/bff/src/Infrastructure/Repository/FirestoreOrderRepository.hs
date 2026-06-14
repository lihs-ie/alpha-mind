module Infrastructure.Repository.FirestoreOrderRepository (
  FirestoreOrderRepositoryEnv (..),
  OrderQueryFilter (..),
  listOrders,
  getOrderByIdentifier,
)
where

import Data.Int (Int64)
import Data.Text (Text)
import Domain.Order.Order (
  OrderDetail (..),
  OrderSide (..),
  OrderStatus (..),
  OrderSummary (..),
 )
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext (..),
  FirestoreError,
  FromFirestore (..),
  QueryFilter (..),
  QueryOrder (..),
  SortDirection (..),
  ToFirestoreValue (..),
  requireField,
 )
import Persistence.Firestore qualified as Firestore

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

-- | Environment for reading the @orders@ Firestore collection.
newtype FirestoreOrderRepositoryEnv = FirestoreOrderRepositoryEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Query filter
-- ---------------------------------------------------------------------------

-- | Optional filters for the order list query.
data OrderQueryFilter = OrderQueryFilter
  { statusFilter :: Maybe Text
  -- ^ Filter by order status (e.g. "PROPOSED").
  , symbolFilter :: Maybe Text
  -- ^ Filter by stock symbol.
  , limitCount :: Int
  -- ^ Maximum number of results (default 50).
  }

-- ---------------------------------------------------------------------------
-- FromFirestore instances
-- ---------------------------------------------------------------------------

instance FromFirestore OrderSummary where
  fromFirestoreFields fieldMap = do
    identifierValue <- requireField "identifier" fieldMap
    symbolValue <- requireField "symbol" fieldMap
    sideText <- requireField "side" fieldMap
    sideValue <- parseSide sideText
    qtyInt <- requireField "qty" fieldMap :: Either Text Int64
    statusText <- requireField "status" fieldMap
    statusValue <- parseStatus statusText
    createdAtValue <- requireField "createdAt" fieldMap
    pure
      OrderSummary
        { identifier = identifierValue
        , symbol = symbolValue
        , side = sideValue
        , qty = fromIntegral qtyInt
        , status = statusValue
        , createdAt = createdAtValue
        }

instance FromFirestore OrderDetail where
  fromFirestoreFields fieldMap = do
    identifierValue <- requireField "identifier" fieldMap
    symbolValue <- requireField "symbol" fieldMap
    sideText <- requireField "side" fieldMap
    sideValue <- parseSide sideText
    qtyInt <- requireField "qty" fieldMap :: Either Text Int64
    statusText <- requireField "status" fieldMap
    statusValue <- parseStatus statusText
    createdAtValue <- requireField "createdAt" fieldMap
    traceValue <- requireField "trace" fieldMap
    maybeReasonCode <- requireField "reasonCode" fieldMap
    maybeBrokerOrder <- requireField "brokerOrder" fieldMap
    maybeUpdatedAt <- requireField "updatedAt" fieldMap
    pure
      OrderDetail
        { identifier = identifierValue
        , symbol = symbolValue
        , side = sideValue
        , qty = fromIntegral qtyInt
        , status = statusValue
        , createdAt = createdAtValue
        , trace = traceValue
        , reasonCode = maybeReasonCode
        , brokerOrder = maybeBrokerOrder
        , updatedAt = maybeUpdatedAt
        }

-- ---------------------------------------------------------------------------
-- Repository operations
-- ---------------------------------------------------------------------------

{- | List orders with optional filters.

Queries the @orders@ collection ordered by @createdAt DESC@.
Cursor-based pagination is not implemented in MVP (returns up to @limit@ items).
-}
listOrders ::
  FirestoreOrderRepositoryEnv ->
  OrderQueryFilter ->
  IO (Either FirestoreError [OrderSummary])
listOrders orderRepositoryEnv queryFilter = do
  let filters = buildFilters queryFilter
      orders = [QueryOrder{orderField = "createdAt", orderDirection = Descending}]
      limitValue = max 1 (min 200 queryFilter.limitCount)
  Firestore.runQuery
    orderRepositoryEnv.firestoreContext
    (CollectionName "orders")
    filters
    orders
    limitValue
    Nothing

{- | Get a single order by its ULID identifier.

Returns 'Nothing' if the document does not exist.
-}
getOrderByIdentifier ::
  FirestoreOrderRepositoryEnv ->
  Text ->
  IO (Either FirestoreError (Maybe OrderDetail))
getOrderByIdentifier orderRepositoryEnv orderIdentifier =
  Firestore.getDocument
    orderRepositoryEnv.firestoreContext
    (CollectionName "orders")
    (DocumentId orderIdentifier)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

buildFilters :: OrderQueryFilter -> [QueryFilter]
buildFilters queryFilter =
  statusFilters <> symbolFilters
 where
  statusFilters =
    case queryFilter.statusFilter of
      Nothing -> []
      Just statusText ->
        [QueryFilterEqual{filterField = "status", filterValue = toValue statusText}]
  symbolFilters =
    case queryFilter.symbolFilter of
      Nothing -> []
      Just symbolText ->
        [QueryFilterEqual{filterField = "symbol", filterValue = toValue symbolText}]

parseSide :: Text -> Either Text OrderSide
parseSide "BUY" = Right Buy
parseSide "SELL" = Right Sell
parseSide unknown = Left ("Unknown order side: " <> unknown)

parseStatus :: Text -> Either Text OrderStatus
parseStatus "PROPOSED" = Right Proposed
parseStatus "APPROVED" = Right Approved
parseStatus "REJECTED" = Right Rejected
parseStatus "EXECUTED" = Right Executed
parseStatus "FAILED" = Right Failed
parseStatus unknown = Left ("Unknown order status: " <> unknown)
