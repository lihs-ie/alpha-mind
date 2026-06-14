{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

{- | Servant API type definition for the agent-orchestrator service.

 Defines 'AgentOrchestratorAPI' as the business API (excluding the standard
 health endpoints which are added by 'App.Bootstrap.runHttpService').

 Endpoints:
   * @POST /pubsub/events@ — Pub/Sub push subscription receiver
-}
module Presentation.Api (
  AgentOrchestratorAPI,
  agentOrchestratorApiProxy,
  agentOrchestratorServer,
) where

import Data.Aeson (ToJSON (..), Value, encode, object, (.=))
import Data.Text (Text)
import Presentation.AppM (AppEnv)
import Presentation.PubSubHandler (
  PubSubPushResult (..),
  handlePubSubPush,
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
-- API type (Must-08)
-- ---------------------------------------------------------------------------

{- | The agent-orchestrator business API.

 @POST /pubsub/events@: Receives a Pub/Sub push envelope as JSON.
 Servant parses the body as 'Value' (generic JSON) and we re-encode it as
 'ByteString' to pass to 'decodePubSubPush'.  This avoids defining a
 bespoke @FromJSON@ for the push envelope at the Servant layer, while still
 allowing structural validation inside the handler.
-}
type AgentOrchestratorAPI =
  "pubsub"
    :> "events"
    :> ReqBody '[JSON] Value
    :> Post '[JSON] PubSubPushResponse

agentOrchestratorApiProxy :: Proxy AgentOrchestratorAPI
agentOrchestratorApiProxy = Proxy

-- ---------------------------------------------------------------------------
-- Response type
-- ---------------------------------------------------------------------------

newtype PubSubPushResponse = PubSubPushResponse
  { result :: Text
  }

instance ToJSON PubSubPushResponse where
  toJSON response = object ["result" .= response.result]

-- ---------------------------------------------------------------------------
-- Server (Must-09)
-- ---------------------------------------------------------------------------

agentOrchestratorServer :: AppEnv -> Server AgentOrchestratorAPI
agentOrchestratorServer = pubSubPushHandler

pubSubPushHandler :: AppEnv -> Value -> Handler PubSubPushResponse
pubSubPushHandler appEnv requestValue = do
  -- Re-encode the Aeson Value back to ByteString so decodePubSubPush can
  -- parse the Pub/Sub push envelope structure (including base64 message.data).
  let body = encode requestValue
  pushResult <- handlePubSubPush appEnv body
  pure (PubSubPushResponse{result = pushResultToText pushResult})

pushResultToText :: PubSubPushResult -> Text
pushResultToText PubSubPushOrchestrationSucceeded = "orchestration_succeeded"
pushResultToText PubSubPushOrchestrationDuplicate = "orchestration_duplicate"
pushResultToText (PubSubPushSchemaInvalid _) = "schema_invalid"
pushResultToText (PubSubPushUnknownEventType _) = "unknown_event_type"
pushResultToText (PubSubPushOrchestrationFailed _) = "orchestration_failed"
