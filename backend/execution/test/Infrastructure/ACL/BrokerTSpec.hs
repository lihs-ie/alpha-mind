module Infrastructure.ACL.BrokerTSpec (spec) where

import Control.Exception (throwIO, toException)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Domain.OrderExecution.Aggregate (ExecutionRequest (..))
import Domain.OrderExecution.BrokerPort (BrokerPort (..))
import Domain.OrderExecution.ReasonCode (ReasonCode (..))
import Infrastructure.ACL.BrokerT (
  BrokerEnv (..),
  classifyBrokerResponse,
  runBrokerT,
 )
import Network.HTTP.Client (
  HttpException (..),
  HttpExceptionContent (..),
  Request,
  Response,
  defaultRequest,
 )
import Network.HTTP.Client.Internal (CookieJar (..), Response (..), ResponseClose (..))
import Network.HTTP.Types (Status (..), http11, status200)
import Test.Hspec (Spec, describe, it, shouldBe)

-- ---------------------------------------------------------------------------
-- Test fixtures
-- ---------------------------------------------------------------------------

testRequest :: ExecutionRequest
testRequest =
  ExecutionRequest
    { symbol = "AAPL"
    , side = "buy"
    , qty = 10
    }

buildJsonResponse :: Status -> Aeson.Value -> Response ByteString.Lazy.ByteString
buildJsonResponse statusValue body =
  Response
    { responseStatus = statusValue
    , responseVersion = http11
    , responseHeaders = []
    , responseBody = Aeson.encode body
    , responseCookieJar = CJ []
    , responseClose' = ResponseClose (pure ())
    , responseOriginalRequest = defaultRequest
    , responseEarlyHints = []
    }

makeBrokerEnvironment ::
  (Request -> IO (Response ByteString.Lazy.ByteString)) ->
  BrokerEnv
makeBrokerEnvironment fakeHttp =
  BrokerEnv
    { apiToken = "test-api-token"
    , baseUrl = "https://paper-api.alpaca.markets"
    , timeoutSeconds = 30
    , httpExecute = fakeHttp
    }

-- | Build a Response () with a given status code, for use in StatusCodeException.
fakeEmptyResponseWithStatus :: Int -> Response ()
fakeEmptyResponseWithStatus statusCodeValue =
  Response
    { responseStatus = Status statusCodeValue "status"
    , responseVersion = http11
    , responseHeaders = []
    , responseBody = ()
    , responseCookieJar = CJ []
    , responseClose' = ResponseClose (pure ())
    , responseOriginalRequest = defaultRequest
    , responseEarlyHints = []
    }

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
  describe "Infrastructure.ACL.BrokerT" $ do
    -- TST-ACL-001: success path
    describe "TST-ACL-001: submitBrokerOrder success → Right brokerOrderId" $ do
      it "returns Right brokerOrderId when httpExecute returns 2xx with id field" $ do
        let successBody =
              Aeson.object
                [ "id" Aeson..= ("broker-order-id" :: Text)
                , "status" Aeson..= ("accepted" :: Text)
                ]
            fakeHttp _ = pure (buildJsonResponse status200 successBody)
            environment = makeBrokerEnvironment fakeHttp
        result <- runBrokerT environment (submitBrokerOrder testRequest)
        result `shouldBe` Right "broker-order-id"

    -- TST-ACL-002: timeout → Left ExecutionBrokerTimeout
    describe "TST-ACL-002: submitBrokerOrder timeout → Left ExecutionBrokerTimeout" $ do
      it "returns Left ExecutionBrokerTimeout when httpExecute throws ResponseTimeout" $ do
        let fakeHttp _ =
              throwIO (HttpExceptionRequest defaultRequest ResponseTimeout)
            environment = makeBrokerEnvironment fakeHttp
        result <- runBrokerT environment (submitBrokerOrder testRequest)
        result `shouldBe` Left ExecutionBrokerTimeout

    -- TST-ACL-003: classifyBrokerResponse pure function — 5 cases
    describe "TST-ACL-003: classifyBrokerResponse pure — 5 classification cases" $ do
      it "maps ResponseTimeout → ExecutionBrokerTimeout" $
        classifyBrokerResponse (HttpExceptionRequest defaultRequest ResponseTimeout)
          `shouldBe` ExecutionBrokerTimeout

      it "maps StatusCodeException 400 → ExecutionBrokerRejected" $
        classifyBrokerResponse
          ( HttpExceptionRequest
              defaultRequest
              (StatusCodeException (fakeEmptyResponseWithStatus 400) "")
          )
          `shouldBe` ExecutionBrokerRejected

      it "maps StatusCodeException 422 → ExecutionMarketClosed" $
        classifyBrokerResponse
          ( HttpExceptionRequest
              defaultRequest
              (StatusCodeException (fakeEmptyResponseWithStatus 422) "")
          )
          `shouldBe` ExecutionMarketClosed

      it "maps StatusCodeException 403 → ExecutionInsufficientFunds" $
        classifyBrokerResponse
          ( HttpExceptionRequest
              defaultRequest
              (StatusCodeException (fakeEmptyResponseWithStatus 403) "")
          )
          `shouldBe` ExecutionInsufficientFunds

      it "maps ConnectionFailure → InternalError" $
        classifyBrokerResponse
          ( HttpExceptionRequest
              defaultRequest
              (ConnectionFailure (toException (userError "network down")))
          )
          `shouldBe` InternalError

    -- TST-ACL-004: non-retryable market-closed error → Left ExecutionMarketClosed, no retry
    describe "TST-ACL-004: non-retryable market-closed error → Left ExecutionMarketClosed" $ do
      it "returns Left ExecutionMarketClosed and calls httpExecute exactly once (no retry)" $ do
        callCountRef <- newIORef (0 :: Int)
        let fakeHttp _ = do
              modifyIORef' callCountRef (+ 1)
              throwIO
                ( HttpExceptionRequest
                    defaultRequest
                    (StatusCodeException (fakeEmptyResponseWithStatus 422) "")
                )
            environment = makeBrokerEnvironment fakeHttp
        result <- runBrokerT environment (submitBrokerOrder testRequest)
        result `shouldBe` Left ExecutionMarketClosed
        callCount <- readIORef callCountRef
        callCount `shouldBe` 1
