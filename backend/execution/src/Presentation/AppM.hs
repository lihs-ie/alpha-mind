{-# LANGUAGE GeneralizedNewtypeDeriving #-}

{- | Application monad for the execution service.

 'AppM' is a flat @ReaderT AppEnv IO@ that provides all Port instances
 required by 'executeOrder':

   * 'OrderExecutionRepository'      → FirestoreOrderExecutionRepositoryT
   * 'BrokerPort'                    → BrokerT
   * 'ExecutionEventPublisher'       → PubSubExecutionEventPublisherT
   * 'DemoCompletionEventPublisher'  → PubSubExecutionEventPublisherT
   * 'DemoRunEvaluationRepository'   → stub (no Firestore impl yet, waived)

 Each instance delegates to the corresponding transformer by extracting the
 relevant sub-environment from 'AppEnv' and calling its @run*T@ function.
-}
module Presentation.AppM (
  -- * Application environment
  AppEnv (..),

  -- * Application monad
  AppM (..),
  runAppM,

  -- * Environment construction
  buildAppEnv,
) where

import Config.Env (CommonRuntimeEnv (..), loadCommonRuntimeEnv, optionalTextEnv, requireTextEnv)
import Control.Monad.IO.Class (MonadIO (liftIO))
import Control.Monad.Trans.Reader (ReaderT (..), ask, runReaderT)
import Data.Maybe (fromMaybe)
import Domain.OrderExecution.Aggregate (
  OrderExecutionRepository (..),
 )
import Domain.OrderExecution.Aggregate qualified as ExecutionRepo
import Domain.OrderExecution.BrokerPort (BrokerPort (..))
import Domain.OrderExecution.DemoRunEvaluation (
  DemoRunEvaluation,
  DemoRunEvaluationIdentifier (..),
  DemoRunEvaluationRepository (..),
 )
import Infrastructure.ACL.BrokerT (BrokerEnv (..), runBrokerT)
import Infrastructure.Publisher.PubSubExecutionEventPublisher (
  PubSubExecutionEventPublisherEnv (..),
  runPubSubExecutionEventPublisherT,
 )
import Infrastructure.Repository.FirestoreOrderExecutionRepository (
  FirestoreOrderExecutionEnv (..),
  runFirestoreOrderExecutionRepositoryT,
 )
import Messaging.PubSub (PubSubPublisher (..))
import Network.HTTP.Client (httpLbs)
import Network.HTTP.Client.TLS (newTlsManager)
import Observability.Logging (LogEnv, initLogger)
import Persistence.Firestore (FirestoreContext (..))
import UseCase.CompleteDemoRun (
  DemoCompletionEventPublisher (..),
 )
import UseCase.ExecuteOrder (
  ExecutionEventPublisher (..),
 )

-- ---------------------------------------------------------------------------
-- Application environment
-- ---------------------------------------------------------------------------

{- | AppEnv holds all sub-environments needed by AppM port instances.
 Constructed once at startup via 'buildAppEnv'.
-}
data AppEnv = AppEnv
  { firestoreOrderExecutionEnv :: FirestoreOrderExecutionEnv
  , brokerEnv :: BrokerEnv
  , pubSubExecutionEnv :: PubSubExecutionEventPublisherEnv
  , logEnv :: LogEnv
  }

-- ---------------------------------------------------------------------------
-- Application monad
-- ---------------------------------------------------------------------------

newtype AppM a = AppM {unAppM :: ReaderT AppEnv IO a}
  deriving newtype (Functor, Applicative, Monad, MonadIO)

runAppM :: AppEnv -> AppM a -> IO a
runAppM appEnv action = runReaderT (unAppM action) appEnv

-- ---------------------------------------------------------------------------
-- OrderExecutionRepository instance
-- Delegates to FirestoreOrderExecutionRepositoryT.
-- ---------------------------------------------------------------------------

instance OrderExecutionRepository AppM where
  findExecution executionIdentifier = AppM $ do
    appEnv <- ask
    liftIO $
      runFirestoreOrderExecutionRepositoryT appEnv.firestoreOrderExecutionEnv $
        ExecutionRepo.findExecution executionIdentifier

  findExecutionsByStatus executionStatus = AppM $ do
    appEnv <- ask
    liftIO $
      runFirestoreOrderExecutionRepositoryT appEnv.firestoreOrderExecutionEnv $
        ExecutionRepo.findExecutionsByStatus executionStatus

  searchExecutions criteria = AppM $ do
    appEnv <- ask
    liftIO $
      runFirestoreOrderExecutionRepositoryT appEnv.firestoreOrderExecutionEnv $
        ExecutionRepo.searchExecutions criteria

  persistExecution execution = AppM $ do
    appEnv <- ask
    liftIO $
      runFirestoreOrderExecutionRepositoryT appEnv.firestoreOrderExecutionEnv $
        ExecutionRepo.persistExecution execution

  terminateExecution executionIdentifier = AppM $ do
    appEnv <- ask
    liftIO $
      runFirestoreOrderExecutionRepositoryT appEnv.firestoreOrderExecutionEnv $
        ExecutionRepo.terminateExecution executionIdentifier

-- ---------------------------------------------------------------------------
-- BrokerPort instance
-- Delegates to BrokerT.
-- ---------------------------------------------------------------------------

instance BrokerPort AppM where
  submitBrokerOrder executionRequest = AppM $ do
    appEnv <- ask
    liftIO $ runBrokerT appEnv.brokerEnv (submitBrokerOrder executionRequest)

-- ---------------------------------------------------------------------------
-- ExecutionEventPublisher instance
-- Delegates to PubSubExecutionEventPublisherT.
-- ---------------------------------------------------------------------------

instance ExecutionEventPublisher AppM where
  publishOrdersExecuted executionIdentifier brokerOrder executedAt traceValue = AppM $ do
    appEnv <- ask
    liftIO $
      runPubSubExecutionEventPublisherT appEnv.pubSubExecutionEnv $
        publishOrdersExecuted executionIdentifier brokerOrder executedAt traceValue

  publishOrdersExecutionFailed executionIdentifier reasonCode traceValue = AppM $ do
    appEnv <- ask
    liftIO $
      runPubSubExecutionEventPublisherT appEnv.pubSubExecutionEnv $
        publishOrdersExecutionFailed executionIdentifier reasonCode traceValue

-- ---------------------------------------------------------------------------
-- DemoCompletionEventPublisher instance
-- Delegates to PubSubExecutionEventPublisherT.
-- ---------------------------------------------------------------------------

instance DemoCompletionEventPublisher AppM where
  publishHypothesisDemoCompleted hypothesisIdentifier demoRunIdentifier performance traceValue = AppM $ do
    appEnv <- ask
    liftIO $
      runPubSubExecutionEventPublisherT appEnv.pubSubExecutionEnv $
        publishHypothesisDemoCompleted hypothesisIdentifier demoRunIdentifier performance traceValue

-- ---------------------------------------------------------------------------
-- DemoRunEvaluationRepository instance
-- Stub: no Firestore implementation yet. Wired to satisfy constraint; the
-- completeDemoRun entrypoint is not exposed in Issue #49.
-- TODO: implement FirestoreDemoRunEvaluationRepository in a future issue.
-- ---------------------------------------------------------------------------

instance DemoRunEvaluationRepository AppM where
  findDemoRunEvaluation _ = pure Nothing
  persistDemoRunEvaluation _ = pure ()
  terminateDemoRunEvaluation _ = pure ()

-- ---------------------------------------------------------------------------
-- Environment construction
-- ---------------------------------------------------------------------------

{- | Build 'AppEnv' from environment variables.

 Required variables:
   GCP_PROJECT_ID (or GOOGLE_CLOUD_PROJECT) — via loadCommonRuntimeEnv
   SERVICE_VERSION                           — via loadCommonRuntimeEnv
   PORT                                      — via loadCommonRuntimeEnv (default 8080)
   BROKER_API_TOKEN
   BROKER_BASE_URL
   PUBSUB_EXECUTED_TOPIC
   PUBSUB_EXECUTION_FAILED_TOPIC
   PUBSUB_DEMO_COMPLETED_TOPIC

 Optional variables:
   FIRESTORE_DATABASE_ID    (default "(default)")
   BROKER_TIMEOUT_SECONDS   (default 30)
-}
buildAppEnv :: IO AppEnv
buildAppEnv = do
  runtimeEnv <- loadCommonRuntimeEnv "execution"
  logEnvironment <- initLogger runtimeEnv
  let projectIdentifier = runtimeEnv.gcpProjectId

  -- Firestore
  maybeDatabaseIdentifier <- optionalTextEnv "FIRESTORE_DATABASE_ID"
  let databaseIdentifier = fromMaybe "(default)" maybeDatabaseIdentifier
      firestoreContextValue =
        FirestoreContext
          { projectId = projectIdentifier
          , databaseId = databaseIdentifier
          }
      firestoreOrderExecutionEnvironment =
        FirestoreOrderExecutionEnv
          { firestoreContext = firestoreContextValue
          }

  -- Broker HTTP client
  brokerApiTokenValue <- requireTextEnv "BROKER_API_TOKEN"
  brokerBaseUrlValue <- requireTextEnv "BROKER_BASE_URL"
  maybeBrokerTimeoutText <- optionalTextEnv "BROKER_TIMEOUT_SECONDS"
  let brokerTimeoutValue = maybe 30 (read . show) maybeBrokerTimeoutText :: Int
  httpManager <- newTlsManager
  let brokerEnvironment =
        BrokerEnv
          { apiToken = brokerApiTokenValue
          , baseUrl = brokerBaseUrlValue
          , timeoutSeconds = brokerTimeoutValue
          , httpExecute = (`httpLbs` httpManager)
          }

  -- Pub/Sub
  executedTopicNameValue <- requireTextEnv "PUBSUB_EXECUTED_TOPIC"
  executionFailedTopicNameValue <- requireTextEnv "PUBSUB_EXECUTION_FAILED_TOPIC"
  demoCompletedTopicNameValue <- requireTextEnv "PUBSUB_DEMO_COMPLETED_TOPIC"
  let pubSubPublisher =
        PubSubPublisher
          { manager = httpManager
          , projectId = projectIdentifier
          , baseURL = "https://pubsub.googleapis.com/v1/"
          , accessToken = pure ""
          }
      pubSubExecutionEnvironment =
        PubSubExecutionEventPublisherEnv
          { publisher = pubSubPublisher
          , executedTopicName = executedTopicNameValue
          , executionFailedTopicName = executionFailedTopicNameValue
          , demoCompletedTopicName = demoCompletedTopicNameValue
          }

  pure
    AppEnv
      { firestoreOrderExecutionEnv = firestoreOrderExecutionEnvironment
      , brokerEnv = brokerEnvironment
      , pubSubExecutionEnv = pubSubExecutionEnvironment
      , logEnv = logEnvironment
      }
