{- | Pub/Sub push endpoint handler for @orders.proposed@ events.

 Implements @POST /pubsub/orders-proposed@.

 Decode chain:
   1. Raw HTTP body → 'PubSubPushEnvelope' (JSON)
   2. @message.data@ base64 → raw bytes
   3. Raw bytes → 'CloudEvent Value' (decodePubSubPush @Value)
   4. Extract 'OrdersProposedPayload' fields from CloudEvent envelope + payload
   5. Load settings from Firestore (kill switch, risk limits, compliance, exposure)
   6. Call 'checkOrderRisk' via AppM with withRetry (Must-11)

 HTTP status mapping (RULE-RG-PRS-001):
   * 'CheckOrderRiskApproved' / 'CheckOrderRiskRejected' / 'Duplicate' → 200 (ack)
   * schema invalid                                                      → 200 (ack, no re-delivery)
   * retryable failure (3 retries exceeded)                             → 500 (nack)
-}
module Presentation.Subscriber.PubSubOrderRiskSubscriber (
  -- * Result type
  OrderRiskPushResult (..),

  -- * Core logic (IO — testable without Servant)
  processOrderRiskMessageWith,
  processOrderRiskMessage,

  -- * Servant handler
  handleOrdersProposed,

  -- * HTTP status mapping
  orderRiskPushResultToStatus,
) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.Aeson.Types qualified as AesonTypes
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as ByteStringLazy
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (decodePubSubPush)
import Presentation.AppM (AppEnv (..), loadSettings, runAppM)
import Resilience.Retry (defaultRetryPolicyConfig, withRetry)
import Servant (Handler, ServerError (..), err500, throwError)
import UseCase.CheckOrderRisk (
  CheckOrderRiskResult (..),
  CompliancePolicy,
  OrdersProposedPayload (..),
  RiskExposure,
  RiskLimits,
  checkOrderRisk,
 )

-- ---------------------------------------------------------------------------
-- Result type
-- ---------------------------------------------------------------------------

data OrderRiskPushResult
  = OrderRiskCheckSucceeded
  | OrderRiskCheckDuplicate
  | OrderRiskSchemaInvalid Text
  | OrderRiskCheckFailed Text
  deriving stock (Eq, Show)

-- | Maps 'OrderRiskPushResult' to HTTP status (RULE-RG-PRS-001).
orderRiskPushResultToStatus :: OrderRiskPushResult -> Either ServerError OrderRiskPushResult
orderRiskPushResultToStatus OrderRiskCheckSucceeded = Right OrderRiskCheckSucceeded
orderRiskPushResultToStatus OrderRiskCheckDuplicate = Right OrderRiskCheckDuplicate
orderRiskPushResultToStatus (OrderRiskSchemaInvalid message) = Right (OrderRiskSchemaInvalid message)
orderRiskPushResultToStatus (OrderRiskCheckFailed message) =
  Left err500{errBody = "order_risk_check_failed: " <> encodeUtf8Lazy message}

-- ---------------------------------------------------------------------------
-- Core logic (IO — injectable usecase runner for tests)
-- ---------------------------------------------------------------------------

{- | Process a Pub/Sub push body with an injectable settings loader and usecase runner (seam).

 The settings loader and usecase runner arguments allow tests to substitute fake
 implementations without test code entering src/. The production wrapper
 'processOrderRiskMessage' passes the real Firestore-based loader and AppM runner.

 TST-PRES-001: Ack on successful processing.
 TST-PRES-002: Ack on duplicate event.
 TST-PRES-003: Ack (200) on decode failure to prevent re-delivery loop.
 TST-PRES-011: withRetry for retryable failures (max 3, exponential backoff).
-}
processOrderRiskMessageWith ::
  IO (Bool, RiskLimits, CompliancePolicy, RiskExposure) ->
  ( UTCTime ->
    Bool ->
    RiskLimits ->
    CompliancePolicy ->
    RiskExposure ->
    OrdersProposedPayload ->
    IO CheckOrderRiskResult
  ) ->
  ByteString ->
  IO OrderRiskPushResult
processOrderRiskMessageWith loadSettings runUseCase body =
  case decodePubSubPush @Value body of
    Left pubSubError ->
      pure (OrderRiskSchemaInvalid (Text.pack (show pubSubError)))
    Right (CloudEvent{identifier = eventIdentifier, trace = eventTrace, payload = eventPayload}) ->
      case extractOrdersProposedPayload eventIdentifier eventTrace eventPayload of
        Left decodingError ->
          pure (OrderRiskSchemaInvalid decodingError)
        Right payload -> do
          currentTime <- getCurrentTime
          (killSwitchEnabled, riskLimits, compliancePolicy, riskExposure) <- loadSettings
          retryResult <-
            withRetry
              defaultRetryPolicyConfig
              isRetryableCheckResult
              ( do
                  checkOrderRiskResult <-
                    runUseCase
                      currentTime
                      killSwitchEnabled
                      riskLimits
                      compliancePolicy
                      riskExposure
                      payload
                  -- Retryable failures go to Left so withRetry can trigger on them.
                  -- Terminal results (including non-retryable failures) go to Right.
                  case checkOrderRiskResult of
                    CheckOrderRiskFailed message True -> pure (Left (CheckOrderRiskFailed message True))
                    other -> pure (Right other)
              )
          case retryResult of
            Left _ -> pure (OrderRiskCheckFailed "retry_exhausted")
            Right checkOrderRiskResult -> pure (checkResultToPushResult checkOrderRiskResult)
 where
  isRetryableCheckResult :: CheckOrderRiskResult -> Bool
  isRetryableCheckResult (CheckOrderRiskFailed _ True) = True
  isRetryableCheckResult _ = False

{- | Process a Pub/Sub push body, returning an 'OrderRiskPushResult'.

 Uses the real 'runAppM'-based runner and loads settings from Firestore via 'loadSettings'.
-}
processOrderRiskMessage ::
  AppEnv ->
  ByteString ->
  IO OrderRiskPushResult
processOrderRiskMessage appEnv =
  processOrderRiskMessageWith
    (loadSettings appEnv)
    ( \currentTime killSwitchEnabled riskLimits compliancePolicy riskExposure payload ->
        runAppM appEnv $
          checkOrderRisk
            currentTime
            killSwitchEnabled
            riskLimits
            compliancePolicy
            riskExposure
            payload
    )

-- ---------------------------------------------------------------------------
-- Servant handler
-- ---------------------------------------------------------------------------

{- | Servant 'Handler' wrapper around 'processOrderRiskMessage'.

 TST-PRES-001: Ack on success.
 TST-PRES-002: Ack on duplicate.
 TST-PRES-003: Ack (200) on decode failure to prevent re-delivery loop.
-}
handleOrdersProposed ::
  AppEnv ->
  ByteString ->
  Handler OrderRiskPushResult
handleOrdersProposed appEnv body = do
  pushResult <- liftIO (processOrderRiskMessage appEnv body)
  case orderRiskPushResultToStatus pushResult of
    Left serverError -> throwError serverError
    Right successResult -> pure successResult

-- ---------------------------------------------------------------------------
-- CloudEvent payload extraction
-- ---------------------------------------------------------------------------

{- | Extract 'OrdersProposedPayload' from CloudEvent envelope fields.

 The CloudEvent identifier and trace are taken from the envelope (not payload),
 following the CloudEvents spec. Symbol, side, and qty are extracted from payload.
-}
extractOrdersProposedPayload :: ULID -> ULID -> Value -> Either Text OrdersProposedPayload
extractOrdersProposedPayload cloudEventIdentifier cloudEventTrace payloadValue =
  case AesonTypes.parseEither parsePayloadFields payloadValue of
    Left parseError -> Left (Text.pack parseError)
    Right (symbolValue, sideValue, qtyValue) ->
      Right
        OrdersProposedPayload
          { identifier = cloudEventIdentifier
          , symbol = symbolValue
          , side = sideValue
          , qty = qtyValue
          , trace = cloudEventTrace
          }
 where
  parsePayloadFields = Aeson.withObject "OrdersProposedPayload" $ \objectValue -> do
    symbolValue <- objectValue Aeson..: "symbol"
    sideValue <- objectValue Aeson..: "side"
    qtyValue <- objectValue Aeson..: "qty"
    pure (symbolValue, sideValue, qtyValue)

-- ---------------------------------------------------------------------------
-- Result mapping
-- ---------------------------------------------------------------------------

checkResultToPushResult :: CheckOrderRiskResult -> OrderRiskPushResult
checkResultToPushResult CheckOrderRiskApproved = OrderRiskCheckSucceeded
checkResultToPushResult (CheckOrderRiskRejected _) = OrderRiskCheckSucceeded
checkResultToPushResult CheckOrderRiskDuplicate = OrderRiskCheckDuplicate
checkResultToPushResult (CheckOrderRiskFailed message False) = OrderRiskSchemaInvalid message
checkResultToPushResult (CheckOrderRiskFailed message True) = OrderRiskCheckFailed message

-- ---------------------------------------------------------------------------
-- Internal helper
-- ---------------------------------------------------------------------------

encodeUtf8Lazy :: Text -> ByteString
encodeUtf8Lazy = ByteStringLazy.fromStrict . TextEncoding.encodeUtf8
