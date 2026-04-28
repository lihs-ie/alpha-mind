{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module BootstrapSpec (spec) where

import App.Bootstrap (HttpServiceOptions (..), mkApplication)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value, eitherDecode, object, (.=))
import Data.Text (Text)
import Observability.Metrics (initCommonMetrics, observeProcessing)
import Network.Wai.Test (SResponse (simpleBody))
import Servant (Get, PlainText, Proxy (..), Server, type (:>))
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)
import Test.Hspec.Wai (get, shouldRespondWith, with)

type BusinessAPI = "business" :> Get '[PlainText] Text

spec :: Spec
spec =
  with (mkApplication options (Proxy @BusinessAPI) businessServer) $
    describe "App.Bootstrap.mkApplication" $ do
      it "serves the standard health endpoint" $
        get "/healthz" `shouldRespondWith` "ok"

      it "serves the business API" $
        get "/business" `shouldRespondWith` "business-ok"

      it "serves the standard status payload" $ do
        response <- get "/"
        liftIO $
          case eitherDecode (simpleBody response) of
            Left err -> expectationFailure err
            Right actual -> actual `shouldBe` expectedStatusPayload

      it "serves metrics when metricsPath is enabled" $ do
        liftIO $ initCommonMetrics "bootstrap_spec" >>= \metrics -> observeProcessing metrics "success" "none" 0.1
        get "/metrics" `shouldRespondWith` 200

businessServer :: Server BusinessAPI
businessServer =
  pure "business-ok"

options :: HttpServiceOptions BusinessAPI
options =
  HttpServiceOptions
    { serviceName = "shared"
    , serviceVersion = "0.1.0"
    , metricsPath = Just "/metrics"
    , middlewareStack = [id]
    , beforeRun = pure ()
    }

expectedStatusPayload :: Value
expectedStatusPayload =
  object
    [ "service" .= ("shared" :: String)
    , "status" .= ("running" :: String)
    , "version" .= ("0.1.0" :: String)
    , "revision" .= (Nothing :: Maybe String)
    ]
