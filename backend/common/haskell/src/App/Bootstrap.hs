{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fno-hpc #-}

module App.Bootstrap (
  HttpServiceOptions (..),
  runHttpService,
  mkApplication,
)
where

import App.Health (ServiceHealthContext (..), StandardHealthAPI, healthServer)
import Config.Env (CommonRuntimeEnv (..), loadCommonRuntimeEnv)
import Data.Kind (Type)
import Data.Text (Text)
import Data.Text qualified as Text
import Network.HTTP.Types (status200)
import Network.Wai (Application, Middleware, pathInfo, responseLBS)
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setOnException, setPort)
import Observability.Logging (LogContext (..), initLogger, logExceptionWith, logInfoWith)
import Observability.Metrics (getMetrics, initCommonMetrics)
import Servant (HasServer, Proxy (..), Server, serve, (:<|>) (..))

data HttpServiceOptions api = HttpServiceOptions
  { serviceName :: Text
  , serviceVersion :: Text
  , metricsPath :: Maybe Text
  , middlewareStack :: [Middleware]
  , beforeRun :: IO ()
  }

type FullAPI api = StandardHealthAPI :<|> api

fullProxy :: Proxy api -> Proxy (FullAPI api)
fullProxy _ = Proxy

mkApplication ::
  forall (api :: Type).
  (HasServer api '[]) =>
  HttpServiceOptions api ->
  Proxy api ->
  Server api ->
  IO Application
mkApplication options proxy businessServer = do
  pure (mkApplicationWithRevision options Nothing proxy businessServer)

mkApplicationWithRevision ::
  forall (api :: Type).
  (HasServer api '[]) =>
  HttpServiceOptions api ->
  Maybe Text ->
  Proxy api ->
  Server api ->
  Application
mkApplicationWithRevision options revisionValue proxy businessServer =
  let context =
        ServiceHealthContext
          { serviceName = options.serviceName
          , serviceVersion = options.serviceVersion
          , serviceRevision = revisionValue
          }
      fullServer = healthServer context :<|> businessServer
      app = serve (fullProxy proxy) fullServer
   in metricsMiddleware options.metricsPath (foldr ($) app options.middlewareStack)

metricsMiddleware :: Maybe Text -> Middleware
metricsMiddleware Nothing app request sendResponse =
  app request sendResponse
metricsMiddleware (Just metricsPath) app request sendResponse =
  if pathInfo request == [Text.dropWhile (== '/') metricsPath]
    then getMetrics >>= sendResponse . responseLBS status200 [("Content-Type", "text/plain; version=0.0.4")]
    else app request sendResponse

runHttpService ::
  forall (api :: Type).
  (HasServer api '[]) =>
  HttpServiceOptions api ->
  Proxy api ->
  Server api ->
  IO ()
runHttpService options proxy businessServer = do
  runtimeEnv <- loadCommonRuntimeEnv options.serviceName
  logEnv <- initLogger runtimeEnv
  _ <- initCommonMetrics options.serviceName
  beforeRun options
  let context =
        LogContext
          { service = options.serviceName
          , trace = Nothing
          , identifier = Nothing
          , eventType = Nothing
          , reasonCode = Nothing
          , result = Nothing
          , payloadSummary = Nothing
          }
      app = mkApplicationWithRevision options runtimeEnv.revision proxy businessServer
      settings =
        setOnException (\_ exception -> logExceptionWith logEnv context exception) $
          setPort runtimeEnv.port defaultSettings
  logInfoWith logEnv context "service_started"
  runSettings settings app
