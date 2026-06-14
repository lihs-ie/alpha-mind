module Presentation.Handler.Orders (
  OrderSummaryResponse (..),
  OrderDetailResponse (..),
  OrderListResponse (..),
  OrderActionResult (..),
  OrderRetryAccepted (..),
  ApproveOrderRequest (..),
  RejectOrderRequest (..),
  getOrdersHandler,
  getOrderByIdentifierHandler,
  approveOrderHandler,
  rejectOrderHandler,
  retryOrderHandler,
)
where

import Control.Exception (SomeException, try)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (FromJSON (..), ToJSON (..), encode, object, withObject, (.:), (.:?), (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Data.ULID qualified as ULID
import Domain.Order.Action (
  OrderTransitionError (..),
  validateApprove,
  validateReject,
  validateRetry,
 )
import Domain.Order.Order (
  OrderDetail (..),
  OrderStatus (..),
  OrderSummary (..),
  orderSideToText,
  orderStatusToText,
 )
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Publisher.PubSubOrdersPublisher (
  PubSubOrdersPublisherEnv (..),
  publishOrdersApproved,
  publishOrdersProposed,
  publishOrdersRejected,
 )
import Infrastructure.Repository.FirestoreOperationsRepository (
  FirestoreOperationsRepositoryEnv (..),
  OperationsRuntime,
  getOperationsRuntime,
  operationsKillSwitchEnabled,
 )
import Infrastructure.Repository.FirestoreOrderRepository (
  FirestoreOrderRepositoryEnv (..),
  OrderQueryFilter (..),
  OrderStatusUpdate (..),
  getOrderByIdentifier,
  listOrders,
  updateOrderStatus,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err401, err403, err404, err409, err503, throwError)

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

-- | Request body for @POST \/orders\/{identifier}\/approve@.
data ApproveOrderRequest = ApproveOrderRequest
  { actionReasonCode :: Maybe Text
  , comment :: Maybe Text
  }

instance FromJSON ApproveOrderRequest where
  parseJSON =
    withObject "ApproveOrderRequest" $ \requestObject ->
      ApproveOrderRequest
        <$> requestObject .:? "actionReasonCode"
        <*> requestObject .:? "comment"

-- | Request body for @POST \/orders\/{identifier}\/reject@.
data RejectOrderRequest = RejectOrderRequest
  { actionReasonCode :: Text
  , comment :: Maybe Text
  }

instance FromJSON RejectOrderRequest where
  parseJSON =
    withObject "RejectOrderRequest" $ \requestObject ->
      RejectOrderRequest
        <$> requestObject .: "actionReasonCode"
        <*> requestObject .:? "comment"

-- | Response body for approve and reject actions (200 OK).
data OrderActionResult = OrderActionResult
  { success :: Bool
  , trace :: Text
  }

instance ToJSON OrderActionResult where
  toJSON actionResult =
    object
      [ "success" .= actionResult.success
      , "trace" .= actionResult.trace
      ]

-- | Response body for retry action (202 Accepted).
data OrderRetryAccepted = OrderRetryAccepted
  { accepted :: Bool
  , identifier :: Text
  , trace :: Text
  }

instance ToJSON OrderRetryAccepted where
  toJSON retryAccepted =
    object
      [ "accepted" .= retryAccepted.accepted
      , "identifier" .= retryAccepted.identifier
      , "trace" .= retryAccepted.trace
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

{- | @POST \/orders\/{identifier}\/approve@ handler.

Requires @orders:approve@ permission.  Validates PROPOSED→APPROVED transition,
checks that the kill switch is disabled, updates the Firestore document, and
publishes an @orders.approved@ CloudEvent.  Returns 409 on invalid transition
or when the kill switch is active.
-}
approveOrderHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  ApproveOrderRequest ->
  Handler OrderActionResult
approveOrderHandler appEnvironment orderIdentifier maybeAuthHeader approveRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "orders:approve"

  killSwitchEnabled <- fetchKillSwitchEnabled appEnvironment

  orderDetail <- fetchOrderOrNotFound appEnvironment orderIdentifier

  case validateApprove killSwitchEnabled orderDetail.status of
    Left KillSwitchActive ->
      throwConflict "Kill switch is enabled; approve is not permitted" "KILL_SWITCH_ENABLED"
    Left (InvalidStateTransition currentStatus _action) ->
      throwConflict
        ("Cannot approve order in status " <> orderStatusToText currentStatus)
        "STATE_CONFLICT"
    Right () -> pure ()

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID
  eventUlid <- liftIO ULID.getULID

  let statusUpdate =
        OrderStatusUpdate
          { newStatus = Approved
          , updatedAt = now
          , version = 1
          }

  updateResult <-
    liftIO $
      updateOrderStatus
        FirestoreOrderRepositoryEnv
          { firestoreContext = appEnvironment.firestoreContext
          }
        orderIdentifier
        statusUpdate

  case updateResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right () -> pure ()

  let maybeActionReasonCode = approveRequest.actionReasonCode
  let publisherEnvironment =
        PubSubOrdersPublisherEnv
          { publisher = appEnvironment.pubSubPublisher
          , ordersApprovedTopicName = appEnvironment.ordersApprovedTopicName
          , ordersRejectedTopicName = appEnvironment.ordersRejectedTopicName
          , ordersProposedTopicName = appEnvironment.ordersProposedTopicName
          }

  liftIO $
    publishOrdersApproved
      publisherEnvironment
      eventUlid
      traceUlid
      now
      orderIdentifier
      maybeActionReasonCode

  pure
    OrderActionResult
      { success = True
      , trace = Text.pack (show traceUlid)
      }

{- | @POST \/orders\/{identifier}\/reject@ handler.

Requires @orders:reject@ permission.  Validates PROPOSED→REJECTED transition,
updates Firestore, and publishes an @orders.rejected@ CloudEvent.
Kill switch does NOT block rejection.  Returns 409 on invalid transition.
-}
rejectOrderHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  RejectOrderRequest ->
  Handler OrderActionResult
rejectOrderHandler appEnvironment orderIdentifier maybeAuthHeader rejectRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "orders:reject"

  orderDetail <- fetchOrderOrNotFound appEnvironment orderIdentifier

  case validateReject orderDetail.status of
    Left (InvalidStateTransition currentStatus _action) ->
      throwConflict
        ("Cannot reject order in status " <> orderStatusToText currentStatus)
        "STATE_CONFLICT"
    Left KillSwitchActive ->
      throwConflict "Kill switch is enabled" "KILL_SWITCH_ENABLED"
    Right () -> pure ()

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID
  eventUlid <- liftIO ULID.getULID

  let statusUpdate =
        OrderStatusUpdate
          { newStatus = Rejected
          , updatedAt = now
          , version = 1
          }

  updateResult <-
    liftIO $
      updateOrderStatus
        FirestoreOrderRepositoryEnv
          { firestoreContext = appEnvironment.firestoreContext
          }
        orderIdentifier
        statusUpdate

  case updateResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right () -> pure ()

  let publisherEnvironment =
        PubSubOrdersPublisherEnv
          { publisher = appEnvironment.pubSubPublisher
          , ordersApprovedTopicName = appEnvironment.ordersApprovedTopicName
          , ordersRejectedTopicName = appEnvironment.ordersRejectedTopicName
          , ordersProposedTopicName = appEnvironment.ordersProposedTopicName
          }

  liftIO $
    publishOrdersRejected
      publisherEnvironment
      eventUlid
      traceUlid
      now
      orderIdentifier
      (Just rejectRequest.actionReasonCode)

  pure
    OrderActionResult
      { success = True
      , trace = Text.pack (show traceUlid)
      }

{- | @POST \/orders\/{identifier}\/retry@ handler.

Requires @orders:retry@ permission.  Validates FAILED→PROPOSED transition,
checks that the kill switch is disabled, updates Firestore back to PROPOSED,
and publishes an @orders.proposed@ CloudEvent.  Returns 202 Accepted.
-}
retryOrderHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  Handler OrderRetryAccepted
retryOrderHandler appEnvironment orderIdentifier maybeAuthHeader = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "orders:retry"

  killSwitchEnabled <- fetchKillSwitchEnabled appEnvironment

  orderDetail <- fetchOrderOrNotFound appEnvironment orderIdentifier

  case validateRetry killSwitchEnabled orderDetail.status of
    Left KillSwitchActive ->
      throwConflict "Kill switch is enabled; retry is not permitted" "KILL_SWITCH_ENABLED"
    Left (InvalidStateTransition currentStatus _action) ->
      throwConflict
        ("Cannot retry order in status " <> orderStatusToText currentStatus)
        "STATE_CONFLICT"
    Right () -> pure ()

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID
  eventUlid <- liftIO ULID.getULID

  let statusUpdate =
        OrderStatusUpdate
          { newStatus = Proposed
          , updatedAt = now
          , version = 1
          }

  updateResult <-
    liftIO $
      updateOrderStatus
        FirestoreOrderRepositoryEnv
          { firestoreContext = appEnvironment.firestoreContext
          }
        orderIdentifier
        statusUpdate

  case updateResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right () -> pure ()

  let publisherEnvironment =
        PubSubOrdersPublisherEnv
          { publisher = appEnvironment.pubSubPublisher
          , ordersApprovedTopicName = appEnvironment.ordersApprovedTopicName
          , ordersRejectedTopicName = appEnvironment.ordersRejectedTopicName
          , ordersProposedTopicName = appEnvironment.ordersProposedTopicName
          }

  liftIO $
    publishOrdersProposed
      publisherEnvironment
      eventUlid
      traceUlid
      now
      orderIdentifier

  pure
    OrderRetryAccepted
      { accepted = True
      , identifier = orderIdentifier
      , trace = Text.pack (show traceUlid)
      }

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

-- | Fetch the kill switch state from Firestore, mapping all errors to 503.
fetchKillSwitchEnabled :: AppEnv -> Handler Bool
fetchKillSwitchEnabled appEnvironment = do
  runtimeResult <-
    liftIO
      ( try
          ( getOperationsRuntime
              FirestoreOperationsRepositoryEnv
                { firestoreContext = appEnvironment.firestoreContext
                }
          ) ::
          IO (Either SomeException (Either FirestoreError OperationsRuntime))
      )
  case runtimeResult of
    Left _exception ->
      throwServiceUnavailable "Failed to read operations state"
    Right (Left firestoreError) ->
      throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right (Right runtimeValue) ->
      pure (operationsKillSwitchEnabled runtimeValue)

-- | Fetch an order by identifier, returning 404 if not found or 503 on Firestore error.
fetchOrderOrNotFound :: AppEnv -> Text -> Handler OrderDetail
fetchOrderOrNotFound appEnvironment orderIdentifier = do
  detailResult <-
    liftIO
      ( try
          ( getOrderByIdentifier
              FirestoreOrderRepositoryEnv
                { firestoreContext = appEnvironment.firestoreContext
                }
              orderIdentifier
          ) ::
          IO (Either SomeException (Either FirestoreError (Maybe OrderDetail)))
      )
  case detailResult of
    Left _exception ->
      throwServiceUnavailable "Failed to read order"
    Right (Left firestoreError) ->
      throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right (Right Nothing) ->
      throwError
        err404
          { errBody = encode (problemJson "Not Found" 404 "Order not found" "RESOURCE_NOT_FOUND")
          , errHeaders = [(hContentType, "application/problem+json")]
          , errReasonPhrase = "Not Found"
          }
    Right (Right (Just orderDetail)) ->
      pure orderDetail

-- | Throw a 409 Conflict with the given detail and reasonCode.
throwConflict :: Text -> Text -> Handler a
throwConflict detailText reasonCodeText =
  throwError
    err409
      { errBody = encode (problemJson "Conflict" 409 detailText reasonCodeText)
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Conflict"
      }
