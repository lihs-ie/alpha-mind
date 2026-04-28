{-# LANGUAGE OverloadedStrings #-}

module HealthSpec (spec) where

import App.Health (
  ServiceHealthContext (..),
  StandardHealthAPI,
  healthServer,
 )
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value, eitherDecode, object, (.=))
import Network.Wai (Application)
import Network.Wai.Test (SResponse (simpleBody))
import Servant (Proxy (Proxy), serve)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)
import Test.Hspec.Wai (get, shouldRespondWith, with)

spec :: Spec
spec =
  with (pure app) $ do
    describe "GET /healthz" $
      it "returns ok" $
        get "/healthz"
          `shouldRespondWith` "ok"

    describe "GET /" $
      it "returns the standard service status payload" $ do
        response <- get "/"
        liftIO $
          case eitherDecode (simpleBody response) of
            Left errorMessage ->
              expectationFailure errorMessage
            Right actual ->
              actual `shouldBe` expectedStatusPayload

app :: Application
app =
  serve
    (Proxy :: Proxy StandardHealthAPI)
    ( healthServer
        ServiceHealthContext
          { serviceName = "shared"
          , serviceVersion = "0.1.0"
          , serviceRevision = Just "rev-1"
          }
    )

expectedStatusPayload :: Value
expectedStatusPayload =
  object
    [ "service" .= ("shared" :: String)
    , "status" .= ("running" :: String)
    , "version" .= ("0.1.0" :: String)
    , "revision" .= ("rev-1" :: String)
    ]
