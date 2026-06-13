{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

{- | Servant API type definition for the audit-log service.

 Defines 'AuditLogAPI' as the business API (excluding the standard health
 endpoints which are added by 'App.Bootstrap.mkApplication').

 Endpoints:
   * @POST /pubsub/events@ — Pub/Sub push subscription receiver
-}
module Presentation.Api (
  AuditLogAPI,
  auditLogApiProxy,
  auditLogServer,
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
-- API type
-- ---------------------------------------------------------------------------

{- | The audit-log business API.

 @POST /pubsub/events@: Receives a Pub/Sub push envelope as JSON.
 Servant parses the body as 'Value' (generic JSON) and we re-encode it as
 'ByteString' to pass to 'decodePubSubPush'.  This avoids defining a
 bespoke @FromJSON@ for the push envelope at the Servant layer, while still
 allowing structural validation inside the handler.
-}
type AuditLogAPI =
  "pubsub"
    :> "events"
    :> ReqBody '[JSON] Value
    :> Post '[JSON] PubSubPushResponse

auditLogApiProxy :: Proxy AuditLogAPI
auditLogApiProxy = Proxy

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

auditLogServer :: AppEnv -> Server AuditLogAPI
auditLogServer = pubSubPushHandler

pubSubPushHandler :: AppEnv -> Value -> Handler PubSubPushResponse
pubSubPushHandler appEnv requestValue = do
  -- Re-encode the Aeson Value back to ByteString so decodePubSubPush can
  -- parse the Pub/Sub push envelope structure (including base64 message.data).
  let body = encode requestValue
  pushResult <- handlePubSubPush appEnv body
  pure (PubSubPushResponse{result = pushResultToText pushResult})

pushResultToText :: PubSubPushResult -> Text
pushResultToText PubSubPushRecorded = "recorded"
pushResultToText PubSubPushDuplicate = "duplicate"
pushResultToText (PubSubPushSchemaInvalid _) = "schema_invalid"
pushResultToText (PubSubPushWriteFailed _) = "write_failed"
pushResultToText (PubSubPushDomainError _) = "domain_error"
