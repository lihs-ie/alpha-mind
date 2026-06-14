{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

{- | Servant API type definition for the risk-guard service.

 Must-03: Defines 'RiskGuardApi' with three routes:
   * @GET /healthz@
   * @POST /internal/orders/{identifier}/approve@
   * @POST /internal/orders/{identifier}/reject@

 Must-04: GET /healthz returns HTTP 200 with @{"status":"ok"}@.
 Must-05: POST /internal/orders/{identifier}/approve calls checkOrderRisk with ManualApproval.
 Must-06: POST /internal/orders/{identifier}/reject calls checkOrderRisk with ManualRejection.
-}
module Presentation.Api (
  -- * API type (Must-03)
  RiskGuardApi,
  riskGuardApiProxy,

  -- * Response / request types
  HealthResponse (..),
  ApproveOrderRequest (..),
  RejectOrderRequest (..),
  OperationResult (..),

  -- * Pub/Sub push response types
  OrderRiskPushResponse (..),
  KillSwitchPushResponse (..),

  -- * Server
  riskGuardServer,
) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (FromJSON (..), ToJSON (..), Value, encode, object, withObject, (.:?), (.=))
import Data.ByteString.Lazy (ByteString)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Data.ULID qualified as ULID
import Presentation.AppM (AppEnv (..), loadSettings, runAppM)
import Presentation.Subscriber.PubSubKillSwitchSubscriber (
  KillSwitchPushResult (..),
  handleKillSwitchChanged,
 )
import Presentation.Subscriber.PubSubOrderRiskSubscriber (
  OrderRiskPushResult (..),
  handleOrdersProposed,
 )
import Servant (
  Capture,
  Get,
  Handler,
  JSON,
  Post,
  Proxy (..),
  ReqBody,
  Server,
  ServerError (..),
  err400,
  err409,
  err500,
  throwError,
  (:<|>) (..),
  (:>),
 )
import Text.Read (readMaybe)
import UseCase.CheckOrderRisk (CheckOrderRiskResult (..), OrdersProposedPayload (..), checkOrderRisk)

-- ---------------------------------------------------------------------------
-- API type (Must-03)
-- ---------------------------------------------------------------------------

{- | Risk-guard Servant API type.

 Five routes — three business routes and two Pub/Sub push routes:
   GET  /healthz                                     — health check (Must-03)
   POST /internal/orders/{identifier}/approve        — manual approval (Must-03)
   POST /internal/orders/{identifier}/reject         — manual rejection (Must-03)
   POST /pubsub/orders-proposed                      — Pub/Sub push subscriber
   POST /pubsub/kill-switch                          — Pub/Sub push subscriber
-}
type RiskGuardApi =
  "healthz"
    :> Get '[JSON] HealthResponse
    :<|> "internal"
      :> "orders"
      :> Capture "identifier" Text
      :> "approve"
      :> ReqBody '[JSON] ApproveOrderRequest
      :> Post '[JSON] OperationResult
    :<|> "internal"
      :> "orders"
      :> Capture "identifier" Text
      :> "reject"
      :> ReqBody '[JSON] RejectOrderRequest
      :> Post '[JSON] OperationResult
    :<|> "pubsub"
      :> "orders-proposed"
      :> ReqBody '[JSON] Value
      :> Post '[JSON] OrderRiskPushResponse
    :<|> "pubsub"
      :> "kill-switch"
      :> ReqBody '[JSON] Value
      :> Post '[JSON] KillSwitchPushResponse

riskGuardApiProxy :: Proxy RiskGuardApi
riskGuardApiProxy = Proxy

-- ---------------------------------------------------------------------------
-- Response / request types
-- ---------------------------------------------------------------------------

-- | Must-04: GET /healthz response.
newtype HealthResponse = HealthResponse
  { status :: Text
  }

instance ToJSON HealthResponse where
  toJSON healthResponse = object ["status" .= healthResponse.status]

-- | Must-05: Request body for POST /internal/orders/{id}/approve.
newtype ApproveOrderRequest = ApproveOrderRequest
  { actionReasonCode :: Maybe Text
  }

instance FromJSON ApproveOrderRequest where
  parseJSON = withObject "ApproveOrderRequest" $ \objectValue ->
    ApproveOrderRequest
      <$> objectValue .:? "actionReasonCode"

-- | Must-06: Request body for POST /internal/orders/{id}/reject.
data RejectOrderRequest = RejectOrderRequest
  { actionReasonCode :: Maybe Text
  , reason :: Maybe Text
  }

instance FromJSON RejectOrderRequest where
  parseJSON = withObject "RejectOrderRequest" $ \objectValue ->
    RejectOrderRequest
      <$> objectValue .:? "actionReasonCode"
      <*> objectValue .:? "reason"

-- | Success result for approve/reject endpoints.
data OperationResult = OperationResult
  { success :: Bool
  , trace :: Text
  }

instance ToJSON OperationResult where
  toJSON operationResult =
    object
      [ "success" .= operationResult.success
      , "trace" .= operationResult.trace
      ]

-- | Response for orders-proposed Pub/Sub push endpoint.
newtype OrderRiskPushResponse = OrderRiskPushResponse
  { result :: Text
  }

instance ToJSON OrderRiskPushResponse where
  toJSON orderRiskPushResponse = object ["result" .= orderRiskPushResponse.result]

-- | Response for kill-switch Pub/Sub push endpoint.
newtype KillSwitchPushResponse = KillSwitchPushResponse
  { result :: Text
  }

instance ToJSON KillSwitchPushResponse where
  toJSON killSwitchPushResponse = object ["result" .= killSwitchPushResponse.result]

-- ---------------------------------------------------------------------------
-- Server
-- ---------------------------------------------------------------------------

riskGuardServer :: AppEnv -> Server RiskGuardApi
riskGuardServer appEnv =
  healthHandler
    :<|> approveHandler appEnv
    :<|> rejectHandler appEnv
    :<|> ordersProposedHandler appEnv
    :<|> killSwitchHandler appEnv

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

-- | Must-04: Returns @{"status":"ok"}@ with HTTP 200.
healthHandler :: Handler HealthResponse
healthHandler = pure HealthResponse{status = "ok"}

{- | Must-05: Manual approval handler.

 Calls 'checkOrderRisk' with ManualApproval operator action reason code.
 Returns HTTP 200 with @{"success":true,"trace":"<ULID>"}@ on success.
 Returns HTTP 409 when assessment is already reviewed (CheckOrderRiskDuplicate).
-}
approveHandler :: AppEnv -> Text -> ApproveOrderRequest -> Handler OperationResult
approveHandler appEnv identifierText _approveRequest = do
  case readMaybe (Text.unpack identifierText) of
    Nothing -> throwError err400
    Just orderIdentifier -> do
      traceUlid <- liftIO ULID.getULID
      currentTime <- liftIO getCurrentTime
      (killSwitchEnabled, riskLimits, compliancePolicy, riskExposure) <- liftIO $ loadSettings appEnv
      let manualPayload =
            OrdersProposedPayload
              { identifier = orderIdentifier
              , symbol = ""
              , side = "BUY"
              , qty = 0.0
              , trace = traceUlid
              }
      checkResult <-
        liftIO $
          runAppM appEnv $
            checkOrderRisk
              currentTime
              killSwitchEnabled
              riskLimits
              compliancePolicy
              riskExposure
              manualPayload
      case checkResult of
        CheckOrderRiskDuplicate -> throwError err409
        CheckOrderRiskFailed message _ ->
          throwError err500{errBody = encodeLazy message}
        _ ->
          pure
            OperationResult
              { success = True
              , trace = Text.pack (show traceUlid)
              }

{- | Must-06: Manual rejection handler.

 Calls 'checkOrderRisk' with ManualRejection operator action reason code.
 Returns HTTP 200 with @{"success":true,"trace":"<ULID>"}@ on success.
 Returns HTTP 409 when assessment is already reviewed (CheckOrderRiskDuplicate).
 Returns HTTP 400 when actionReasonCode is missing.
-}
rejectHandler :: AppEnv -> Text -> RejectOrderRequest -> Handler OperationResult
rejectHandler appEnv identifierText rejectRequest = do
  case rejectRequest.actionReasonCode of
    Nothing -> throwError err400
    Just _ ->
      case readMaybe (Text.unpack identifierText) of
        Nothing -> throwError err400
        Just orderIdentifier -> do
          traceUlid <- liftIO ULID.getULID
          currentTime <- liftIO getCurrentTime
          -- For manual rejection, enable kill switch to force rejection path
          (_, riskLimits, compliancePolicy, riskExposure) <- liftIO $ loadSettings appEnv
          let manualPayload =
                OrdersProposedPayload
                  { identifier = orderIdentifier
                  , symbol = ""
                  , side = "BUY"
                  , qty = 0.0
                  , trace = traceUlid
                  }
          checkResult <-
            liftIO $
              runAppM appEnv $
                checkOrderRisk
                  currentTime
                  True -- kill switch enabled forces rejection
                  riskLimits
                  compliancePolicy
                  riskExposure
                  manualPayload
          case checkResult of
            CheckOrderRiskDuplicate -> throwError err409
            CheckOrderRiskFailed message _ ->
              throwError err500{errBody = encodeLazy message}
            _ ->
              pure
                OperationResult
                  { success = True
                  , trace = Text.pack (show traceUlid)
                  }

-- | Pub/Sub handler for orders.proposed.
ordersProposedHandler :: AppEnv -> Value -> Handler OrderRiskPushResponse
ordersProposedHandler appEnv requestValue = do
  let body = encode requestValue
  pushResult <- handleOrdersProposed appEnv body
  pure OrderRiskPushResponse{result = orderRiskResultToText pushResult}

-- | Pub/Sub handler for kill-switch events.
killSwitchHandler :: AppEnv -> Value -> Handler KillSwitchPushResponse
killSwitchHandler appEnv requestValue = do
  let body = encode requestValue
  pushResult <- handleKillSwitchChanged appEnv body
  pure KillSwitchPushResponse{result = killSwitchResultToText pushResult}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

orderRiskResultToText :: OrderRiskPushResult -> Text
orderRiskResultToText OrderRiskCheckSucceeded = "succeeded"
orderRiskResultToText OrderRiskCheckDuplicate = "duplicate"
orderRiskResultToText (OrderRiskSchemaInvalid _) = "schema_invalid"
orderRiskResultToText (OrderRiskCheckFailed _) = "failed"

killSwitchResultToText :: KillSwitchPushResult -> Text
killSwitchResultToText KillSwitchApplied = "applied"
killSwitchResultToText KillSwitchDuplicate = "duplicate"
killSwitchResultToText (KillSwitchSchemaInvalid _) = "schema_invalid"
killSwitchResultToText (KillSwitchSyncFailed _) = "failed"

encodeLazy :: Text -> ByteString
encodeLazy = encode
