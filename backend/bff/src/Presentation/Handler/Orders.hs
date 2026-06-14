module Presentation.Handler.Orders (
  OrderSummaryResponse (..),
  OrderDetailResponse (..),
  OrderListResponse (..),
  getOrdersHandler,
  getOrderByIdentifierHandler,
)
where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (ToJSON (..), encode, object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Domain.Order.Order (
  OrderDetail (..),
  OrderSummary (..),
  orderSideToText,
  orderStatusToText,
 )
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Repository.FirestoreOrderRepository (
  FirestoreOrderRepositoryEnv (..),
  OrderQueryFilter (..),
  getOrderByIdentifier,
  listOrders,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err401, err403, err404, err503, throwError)

-- ---------------------------------------------------------------------------
-- Response types
-- ---------------------------------------------------------------------------

-- | JSON representation of a single order summary item.
data OrderSummaryResponse = OrderSummaryResponse
  { identifier :: Text
  , symbol :: Text
  , side :: Text
  , qty :: Double
  , status :: Text
  , createdAt :: Text
  }

instance ToJSON OrderSummaryResponse where
  toJSON orderResponse =
    object
      [ "identifier" .= orderResponse.identifier
      , "symbol" .= orderResponse.symbol
      , "side" .= orderResponse.side
      , "qty" .= orderResponse.qty
      , "status" .= orderResponse.status
      , "createdAt" .= orderResponse.createdAt
      ]

-- | JSON representation of a single order detail.
data OrderDetailResponse = OrderDetailResponse
  { identifier :: Text
  , symbol :: Text
  , side :: Text
  , qty :: Double
  , status :: Text
  , createdAt :: Text
  , trace :: Text
  , reasonCode :: Maybe Text
  , brokerOrder :: Maybe Text
  , updatedAt :: Maybe Text
  }

instance ToJSON OrderDetailResponse where
  toJSON orderDetail =
    object
      [ "identifier" .= orderDetail.identifier
      , "symbol" .= orderDetail.symbol
      , "side" .= orderDetail.side
      , "qty" .= orderDetail.qty
      , "status" .= orderDetail.status
      , "createdAt" .= orderDetail.createdAt
      , "trace" .= orderDetail.trace
      , "reasonCode" .= orderDetail.reasonCode
      , "brokerOrder" .= orderDetail.brokerOrder
      , "updatedAt" .= orderDetail.updatedAt
      ]

-- | Paginated list of order summaries.
data OrderListResponse = OrderListResponse
  { items :: [OrderSummaryResponse]
  , nextCursor :: Maybe Text
  }

instance ToJSON OrderListResponse where
  toJSON listResponse =
    object
      [ "items" .= listResponse.items
      , "nextCursor" .= listResponse.nextCursor
      ]

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

{- | @GET \/orders@ handler.

Requires @orders:read@ permission.  Supports optional @status@ and @symbol@
filters; @limit@ defaults to 50.  Cursor pagination is MVP-incomplete
(nextCursor always returns Nothing).
-}
getOrdersHandler ::
  AppEnv ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  Maybe Int ->
  Maybe Text ->
  Handler OrderListResponse
getOrdersHandler
  appEnvironment
  maybeAuthHeader
  maybeStatus
  _maybeSymbol
  _maybeFrom
  _maybeTo
  maybeLimit
  _maybeCursor = do
    _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "orders:read"

    let orderQueryFilter =
          OrderQueryFilter
            { statusFilter = maybeStatus
            , symbolFilter = Nothing
            , limitCount = maybe 50 (min 200 . max 1) maybeLimit
            }

    ordersResult <-
      liftIO $
        listOrders
          FirestoreOrderRepositoryEnv
            { firestoreContext = appEnvironment.firestoreContext
            }
          orderQueryFilter

    orderSummaries <- case ordersResult of
      Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
      Right items -> pure items

    pure
      OrderListResponse
        { items = map toOrderSummaryResponse orderSummaries
        , nextCursor = Nothing
        }

{- | @GET \/orders\/{identifier}@ handler.

Requires @orders:read@ permission.  Returns 404 when the order does not exist.
-}
getOrderByIdentifierHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  Handler OrderDetailResponse
getOrderByIdentifierHandler appEnvironment orderIdentifier maybeAuthHeader = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "orders:read"

  detailResult <-
    liftIO $
      getOrderByIdentifier
        FirestoreOrderRepositoryEnv
          { firestoreContext = appEnvironment.firestoreContext
          }
        orderIdentifier

  maybeDetail <- case detailResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right maybeValue -> pure maybeValue

  case maybeDetail of
    Nothing ->
      throwError
        err404
          { errBody = encode (problemJson "Not Found" 404 "Order not found" "RESOURCE_NOT_FOUND")
          , errHeaders = [(hContentType, "application/problem+json")]
          , errReasonPhrase = "Not Found"
          }
    Just orderDetail -> pure (toOrderDetailResponse orderDetail)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

requireAuth :: AppEnv -> Maybe Text -> Text -> Handler VerifiedClaims
requireAuth appEnvironment maybeAuthHeader requiredPermission = do
  rawToken <- extractBearerToken maybeAuthHeader
  let jwtVerifierEnvironment = JwtVerifierEnv{issuerEnv = appEnvironment.jwtIssuerEnv}
  claimsResult <- liftIO $ verifyToken jwtVerifierEnvironment rawToken
  verifiedClaimsValue <- case claimsResult of
    Left verificationError -> throwUnauthorized ("Invalid token: " <> verificationError)
    Right claimsValue -> pure claimsValue
  let hasPermission = requiredPermission `elem` verifiedClaimsValue.permissionClaims
  unless hasPermission $
    throwForbidden ("Missing required permission: " <> requiredPermission)
  pure verifiedClaimsValue

extractBearerToken :: Maybe Text -> Handler Text
extractBearerToken Nothing =
  throwUnauthorized "Authorization header is required"
extractBearerToken (Just headerValue) =
  case Text.stripPrefix "Bearer " headerValue of
    Nothing -> throwUnauthorized "Authorization header must use Bearer scheme"
    Just tokenText -> pure tokenText

throwUnauthorized :: Text -> Handler a
throwUnauthorized detailText =
  throwError
    err401
      { errBody = encode (problemJson "Unauthorized" 401 detailText "AUTH_INVALID_CREDENTIALS")
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Unauthorized"
      }

throwForbidden :: Text -> Handler a
throwForbidden detailText =
  throwError
    err403
      { errBody = encode (problemJson "Forbidden" 403 detailText "AUTH_FORBIDDEN")
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Forbidden"
      }

throwServiceUnavailable :: Text -> Handler a
throwServiceUnavailable detailText =
  throwError
    err503
      { errBody = encode (problemJson "Service Unavailable" 503 detailText "DEPENDENCY_UNAVAILABLE")
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Service Unavailable"
      }

data ProblemJson = ProblemJson
  { problemTitle :: Text
  , problemStatus :: Int
  , problemDetail :: Text
  , problemReasonCode :: Text
  }

instance ToJSON ProblemJson where
  toJSON problemValue =
    object
      [ "type" .= ("about:blank" :: Text)
      , "title" .= problemValue.problemTitle
      , "status" .= problemValue.problemStatus
      , "detail" .= problemValue.problemDetail
      , "reasonCode" .= problemValue.problemReasonCode
      ]

problemJson :: Text -> Int -> Text -> Text -> ProblemJson
problemJson titleText statusCode detailText reasonCodeText =
  ProblemJson
    { problemTitle = titleText
    , problemStatus = statusCode
    , problemDetail = detailText
    , problemReasonCode = reasonCodeText
    }

firestoreErrorToText :: FirestoreError -> Text
firestoreErrorToText (FirestoreErrorDecode message) = "Decode error: " <> message
firestoreErrorToText (FirestoreErrorPermissionDenied message) = "Permission denied: " <> message
firestoreErrorToText (FirestoreErrorTransport message) = "Transport error: " <> message
firestoreErrorToText (FirestoreErrorUnexpected statusCode message) =
  "Unexpected error " <> Text.pack (show statusCode) <> ": " <> message

toOrderSummaryResponse :: OrderSummary -> OrderSummaryResponse
toOrderSummaryResponse orderSummary =
  OrderSummaryResponse
    { identifier = orderSummary.identifier
    , symbol = orderSummary.symbol
    , side = orderSideToText orderSummary.side
    , qty = orderSummary.qty
    , status = orderStatusToText orderSummary.status
    , createdAt = Text.pack (show orderSummary.createdAt)
    }

toOrderDetailResponse :: OrderDetail -> OrderDetailResponse
toOrderDetailResponse orderDetail =
  OrderDetailResponse
    { identifier = orderDetail.identifier
    , symbol = orderDetail.symbol
    , side = orderSideToText orderDetail.side
    , qty = orderDetail.qty
    , status = orderStatusToText orderDetail.status
    , createdAt = Text.pack (show orderDetail.createdAt)
    , trace = orderDetail.trace
    , reasonCode = orderDetail.reasonCode
    , brokerOrder = orderDetail.brokerOrder
    , updatedAt = fmap (Text.pack . show) orderDetail.updatedAt
    }
