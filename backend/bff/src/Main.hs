{- | Entry point for the BFF service.

 Initialises 'AppEnv' from environment variables, then delegates to
 'App.Bootstrap.runHttpService' which:
   * mounts @GET /healthz@ and @GET /@ (standard health API)
   * runs the Warp HTTP server on the port defined by @PORT@
   * installs structured exception logging via katip

 The business API ('BffAPI') is combined with the standard health API
 inside 'runHttpService'; callers only need to supply the business proxy and
 server.
-}
module Main (main) where

import App.Bootstrap (HttpServiceOptions (..), runHttpService)
import Presentation.Api (bffApiProxy, bffServer)
import Presentation.AppM (buildAppEnv)

main :: IO ()
main = do
  appEnv <- buildAppEnv
  runHttpService
    HttpServiceOptions
      { serviceName = "bff"
      , serviceVersion = "0.1.0"
      , metricsPath = Nothing
      , middlewareStack = []
      , beforeRun = pure ()
      }
    bffApiProxy
    (bffServer appEnv)
