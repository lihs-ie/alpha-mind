{- | Entry point for the data-collector service.

 Initialises 'AppEnv' from environment variables, then delegates to
 'App.Bootstrap.runHttpService' which:
   * mounts @GET /healthz@ and @GET /@ (standard health API)
   * runs the Warp HTTP server on the port defined by @PORT@
   * installs structured exception logging via katip

 The business API ('DataCollectorAPI') is combined with the standard health API
 inside 'runHttpService'; callers only need to supply the business proxy and
 server.
-}
module Main (main) where

import App.Bootstrap (HttpServiceOptions (..), runHttpService)
import Presentation.Api (dataCollectorApiProxy, dataCollectorServer)
import Presentation.AppM (buildAppEnv)

main :: IO ()
main = do
  appEnv <- buildAppEnv
  runHttpService
    HttpServiceOptions
      { serviceName = "data-collector"
      , serviceVersion = "0.1.0"
      , metricsPath = Nothing
      , middlewareStack = []
      , beforeRun = pure ()
      }
    dataCollectorApiProxy
    (dataCollectorServer appEnv)
