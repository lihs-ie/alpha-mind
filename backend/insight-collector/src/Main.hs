module Main (main) where

import App.Bootstrap (HttpServiceOptions (..), runHttpService)
import Presentation.Api (insightCollectorApiProxy, insightCollectorServer)
import Presentation.AppM (buildAppEnv)

main :: IO ()
main = do
  appEnv <- buildAppEnv
  runHttpService
    HttpServiceOptions
      { serviceName = "insight-collector"
      , serviceVersion = "0.1.0"
      , metricsPath = Nothing
      , middlewareStack = []
      , beforeRun = pure ()
      }
    insightCollectorApiProxy
    (insightCollectorServer appEnv)
