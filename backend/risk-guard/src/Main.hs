{- | Entry point for the risk-guard service.

 Must-07/09: Reads environment variables, builds AppEnv, and runs:
   * Warp HTTP server (GET /healthz + POST /internal/orders/{id}/approve|reject
     + POST /pubsub/orders-proposed + POST /pubsub/kill-switch)

 Pub/Sub push subscriptions deliver @orders.proposed@ and
 @operation.kill_switch.changed@ events to the HTTP server endpoints.
 These are handled by the same Warp server via the API routes.

 Required environment variables (Must-09):
   PUBSUB_PROJECT_ID             — Pub/Sub GCP project ID
   ORDERS_PROPOSED_SUBSCRIPTION  — orders.proposed subscription name
   KILL_SWITCH_SUBSCRIPTION      — operation.kill_switch.changed subscription name
   FIRESTORE_PROJECT_ID          — Firestore GCP project ID
   PORT                          — HTTP server port (default 8080)
   ORDERS_APPROVED_TOPIC         — orders.approved topic name
   ORDERS_REJECTED_TOPIC         — orders.rejected topic name
-}
module Main (main) where

import App.Bootstrap (HttpServiceOptions (..), runHttpService)
import Config.Env (requireTextEnv)
import Control.Concurrent.Async (concurrently_)
import Presentation.Api (riskGuardApiProxy, riskGuardServer)
import Presentation.AppM (buildAppEnv)

main :: IO ()
main = do
  -- Must-09: Validate required environment variables exist before starting.
  -- Missing variables cause 'requireTextEnv' to throw 'MissingEnv' at startup.
  _pubSubProjectIdentifier <- requireTextEnv "PUBSUB_PROJECT_ID"
  _ordersProposedSubscription <- requireTextEnv "ORDERS_PROPOSED_SUBSCRIPTION"
  _killSwitchSubscription <- requireTextEnv "KILL_SWITCH_SUBSCRIPTION"

  -- Build the full AppEnv from environment variables
  appEnv <- buildAppEnv

  -- Must-07: Run HTTP server with all routes concurrently.
  -- Push subscribers for ORDERS_PROPOSED_SUBSCRIPTION and KILL_SWITCH_SUBSCRIPTION
  -- are handled as HTTP POST routes within the same Warp application.
  -- concurrently_ here ensures the bootstrap action and the server run together.
  concurrently_
    (pure ())
    ( runHttpService
        HttpServiceOptions
          { serviceName = "risk-guard"
          , serviceVersion = "0.1.0"
          , metricsPath = Nothing
          , middlewareStack = []
          , beforeRun = pure ()
          }
        riskGuardApiProxy
        (riskGuardServer appEnv)
    )
