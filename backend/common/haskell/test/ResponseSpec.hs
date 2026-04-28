{-# LANGUAGE OverloadedStrings #-}

module ResponseSpec (spec) where

import App.Response (ToProblemDetails (..), mkErrorResponse, mkProblemDetails)
import Data.Aeson (Value, eitherDecode, object, (.=))
import Data.ByteString.Builder (toLazyByteString)
import Network.HTTP.Types (hContentType, statusCode)
import Network.Wai.Internal (Response (ResponseBuilder))
import Test.Hspec (Spec, describe, it, shouldBe)

data ExampleError = ExampleError

instance ToProblemDetails ExampleError where
  toProblemDetails ExampleError =
    mkProblemDetails "about:blank" "Bad Request" 400 "invalid input" "EXAMPLE_INVALID" False

spec :: Spec
spec =
  describe "App.Response" $
    it "renders RFC7807 style problem responses" $
      case mkErrorResponse ExampleError of
        ResponseBuilder status headers body -> do
          statusCode status `shouldBe` 400
          lookup hContentType headers `shouldBe` Just "application/problem+json"
          eitherDecode (toLazyByteString body) `shouldBe` Right expectedProblem
        _ -> expectationFailure "expected a builder response"

expectedProblem :: Value
expectedProblem =
  object
    [ "type" .= ("about:blank" :: String)
    , "title" .= ("Bad Request" :: String)
    , "status" .= (400 :: Int)
    , "detail" .= ("invalid input" :: String)
    , "reasonCode" .= ("EXAMPLE_INVALID" :: String)
    , "retryable" .= False
    ]

expectationFailure :: String -> IO ()
expectationFailure message =
  fail message
