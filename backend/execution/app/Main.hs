{- | Entry point for the execution service.

 Initialises 'AppEnv' from environment variables, then delegates to
 'App.Bootstrap.runHttpService' which:
   * mounts @GET /healthz@ (standard health API)
   * mounts @POST /pubsub/orders-approved@ (business API)
   * runs the Warp HTTP server on the port defined by @PORT@

 The business API ('ExecutionAPI') is combined with the standard health API
 inside 'runHttpService'; callers only need to supply the business proxy and
 server.
-}
module Main (main) where

import App.Bootstrap (HttpServiceOptions (..), runHttpService)
import Presentation.Api (executionApiProxy, executionServer)
import Presentation.AppM (buildAppEnv)

main :: IO ()
main = do
  appEnv <- buildAppEnv
  runHttpService
    HttpServiceOptions
      { serviceName = "execution"
      , serviceVersion = "0.1.0"
      , metricsPath = Nothing
      , middlewareStack = []
      , beforeRun = pure ()
      }
    executionApiProxy
    (executionServer appEnv)
