{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

{- | Servant API type definition for the execution service.

 Defines 'ExecutionAPI' as the business API (excluding the standard health
 endpoints which are added by 'App.Bootstrap.mkApplication').

 Endpoints:
   * @POST /pubsub/orders-approved@ — Pub/Sub push subscription receiver
-}
module Presentation.Api (
  ExecutionAPI,
  executionApiProxy,
  executionServer,
) where

import Data.Aeson (ToJSON (..), Value, encode, object, (.=))
import Data.Text (Text)
import Presentation.AppM (AppEnv)
import Presentation.PubSubHandler (
  PubSubPushResult (..),
  handleOrdersApproved,
 )
import Servant (
  Handler,
  JSON,
  Post,
  Proxy (..),
  ReqBody,
  Server,
  (:>),
 )

-- ---------------------------------------------------------------------------
-- API type
-- ---------------------------------------------------------------------------

{- | The execution business API.

 @POST /pubsub/orders-approved@: Receives a Pub/Sub push envelope as JSON.
 Servant parses the body as 'Value' (generic JSON) and we re-encode it as
 'ByteString' to pass to 'decodePubSubPush'. This avoids defining a bespoke
 @FromJSON@ for the push envelope at the Servant layer, while still allowing
 structural validation inside the handler.
-}
type ExecutionAPI =
  "pubsub"
    :> "orders-approved"
    :> ReqBody '[JSON] Value
    :> Post '[JSON] PubSubPushResponse

executionApiProxy :: Proxy ExecutionAPI
executionApiProxy = Proxy

-- ---------------------------------------------------------------------------
-- Response type
-- ---------------------------------------------------------------------------

newtype PubSubPushResponse = PubSubPushResponse
  { result :: Text
  }

instance ToJSON PubSubPushResponse where
  toJSON response = object ["result" .= response.result]

-- ---------------------------------------------------------------------------
-- Server
-- ---------------------------------------------------------------------------

executionServer :: AppEnv -> Server ExecutionAPI
executionServer = ordersApprovedHandler

ordersApprovedHandler :: AppEnv -> Value -> Handler PubSubPushResponse
ordersApprovedHandler appEnv requestValue = do
  -- Re-encode the Aeson Value back to ByteString so decodePubSubPush can
  -- parse the Pub/Sub push envelope structure (including base64 message.data).
  let body = encode requestValue
  pushResult <- handleOrdersApproved appEnv body
  pure (PubSubPushResponse{result = pushResultToText pushResult})

pushResultToText :: PubSubPushResult -> Text
pushResultToText PubSubPushExecutionSucceeded = "execution_succeeded"
pushResultToText PubSubPushExecutionDuplicate = "execution_duplicate"
pushResultToText (PubSubPushSchemaInvalid _) = "schema_invalid"
pushResultToText (PubSubPushExecutionRetryable _) = "execution_retryable"
pushResultToText (PubSubPushExecutionFailed _) = "execution_failed"
