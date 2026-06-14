{- | ACL adapter for Broker REST API.

Must-02: BrokerT provides BrokerPort instance.
Must-03: submitBrokerOrder sends POST to broker, returns Right brokerOrderId or Left ReasonCode.
Must-04: BrokerEnv holds baseUrl, timeoutSeconds, httpExecute, apiToken.
Must-05: Timeout → Left ExecutionBrokerTimeout.
Must-06: withRetry wraps HTTP calls.
Must-07: isRetryableForBroker predicate.
Must-08/Must-09: classifyBrokerResponse pure function exported.
Must-10: Auth token injected via BrokerEnv, not hardcoded.
-}
module Infrastructure.ACL.BrokerT (
  -- * Environment
  BrokerEnv (..),

  -- * Monad transformer
  BrokerT (..),
  runBrokerT,

  -- * Pure error classifier (Must-09)
  classifyBrokerResponse,
) where

import Control.Exception (try)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as Aeson.KeyMap
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Domain.OrderExecution.Aggregate (ExecutionRequest (..))
import Domain.OrderExecution.BrokerPort (BrokerPort (..))
import Domain.OrderExecution.ReasonCode (ReasonCode (..))
import Network.HTTP.Client (
  HttpException (..),
  HttpExceptionContent (..),
  Request,
  RequestBody (..),
  Response,
  method,
  parseRequest_,
  requestBody,
  requestHeaders,
  responseBody,
  responseStatus,
 )
import Network.HTTP.Types (statusCode)
import Resilience.Retry (defaultRetryPolicyConfig, withRetry)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

{- | Must-04: Broker adapter environment.
apiToken is injected from Secret Manager (Must-10).
timeoutSeconds controls per-request timeout (Must-05).
httpExecute can be replaced in tests.
-}
data BrokerEnv = BrokerEnv
  { apiToken :: Text
  -- ^ Must-10: Bearer token — injected, never hardcoded
  , baseUrl :: Text
  -- ^ Broker API base URL
  , timeoutSeconds :: Int
  -- ^ Must-05: per-request timeout in seconds
  , httpExecute :: Request -> IO (Response ByteString.Lazy.ByteString)
  -- ^ HTTP transport — replaceable in tests
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype BrokerT m a = BrokerT
  { unBrokerT :: ReaderT BrokerEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runBrokerT :: BrokerEnv -> BrokerT m a -> m a
runBrokerT environment action =
  runReaderT (unBrokerT action) environment

-- ---------------------------------------------------------------------------
-- BrokerPort instance
-- ---------------------------------------------------------------------------

instance BrokerPort (BrokerT IO) where
  submitBrokerOrder executionRequest = BrokerT $ do
    environment <- ask
    liftIO $ submitBrokerOrderIO environment executionRequest

-- ---------------------------------------------------------------------------
-- Core submit logic
-- ---------------------------------------------------------------------------

submitBrokerOrderIO ::
  BrokerEnv ->
  ExecutionRequest ->
  IO (Either ReasonCode Text)
submitBrokerOrderIO environment executionRequest =
  withRetry defaultRetryPolicyConfig isRetryableForBroker $
    callBrokerHttp environment executionRequest

callBrokerHttp ::
  BrokerEnv ->
  ExecutionRequest ->
  IO (Either ReasonCode Text)
callBrokerHttp environment executionRequest = do
  let url = Text.unpack environment.baseUrl <> "/v2/orders"
      body = buildOrderBody executionRequest
      request =
        (parseRequest_ url)
          { method = "POST"
          , requestHeaders =
              [ ("Authorization", "Bearer " <> Text.Encoding.encodeUtf8 environment.apiToken)
              , ("Content-Type", "application/json")
              ]
          , requestBody = RequestBodyLBS (Aeson.encode body)
          }
  responseResult <- try @HttpException (environment.httpExecute request)
  case responseResult of
    Left httpException -> pure (Left (classifyBrokerResponse httpException))
    Right response -> interpretBrokerResponse response

buildOrderBody :: ExecutionRequest -> Value
buildOrderBody executionRequest =
  Aeson.object
    [ "symbol" Aeson..= executionRequest.symbol
    , "side" Aeson..= executionRequest.side
    , "qty" Aeson..= executionRequest.qty
    , "type" Aeson..= ("market" :: Text)
    , "time_in_force" Aeson..= ("day" :: Text)
    ]

interpretBrokerResponse ::
  Response ByteString.Lazy.ByteString ->
  IO (Either ReasonCode Text)
interpretBrokerResponse response = do
  let statusCodeValue = statusCode (responseStatus response)
  if statusCodeValue >= 200 && statusCodeValue < 300
    then case Aeson.decode (responseBody response) of
      Just (Aeson.Object obj) ->
        case Aeson.KeyMap.lookup "id" obj of
          Just (Aeson.String brokerOrderIdentifier) ->
            pure (Right brokerOrderIdentifier)
          _ ->
            pure (Right (Text.pack (show statusCodeValue)))
      _ ->
        pure (Right (Text.pack (show statusCodeValue)))
    else pure (Left (classifyStatusCode statusCodeValue))

-- ---------------------------------------------------------------------------
-- Error classification (pure, Must-08/Must-09)
-- ---------------------------------------------------------------------------

{- | Must-08/Must-09: Classify an HttpException to a ReasonCode.
Pure function — can be tested directly.
-}
classifyBrokerResponse :: HttpException -> ReasonCode
classifyBrokerResponse (HttpExceptionRequest _ exceptionContent) =
  case exceptionContent of
    ResponseTimeout -> ExecutionBrokerTimeout
    ConnectionTimeout -> ExecutionBrokerTimeout
    ConnectionFailure _ -> InternalError
    other -> classifyByContent other
classifyBrokerResponse (InvalidUrlException _ _) = InternalError

classifyByContent :: HttpExceptionContent -> ReasonCode
classifyByContent (StatusCodeException response _) =
  classifyStatusCode (statusCode (responseStatus response))
classifyByContent _ = InternalError

classifyStatusCode :: Int -> ReasonCode
classifyStatusCode statusCodeValue
  | statusCodeValue == 422 = ExecutionMarketClosed
  | statusCodeValue == 403 = ExecutionInsufficientFunds
  | statusCodeValue == 400 = ExecutionBrokerRejected
  | statusCodeValue >= 400 && statusCodeValue < 500 = ExecutionBrokerRejected
  | otherwise = InternalError

-- ---------------------------------------------------------------------------
-- Retry predicate (Must-07)
-- ---------------------------------------------------------------------------

{- | Must-07: isRetryableForBroker — True for transient failures only.
ExecutionBrokerTimeout and InternalError are retryable.
Market-state and funds errors are not retryable.
-}
isRetryableForBroker :: ReasonCode -> Bool
isRetryableForBroker ExecutionBrokerTimeout = True
isRetryableForBroker InternalError = True
isRetryableForBroker _ = False
