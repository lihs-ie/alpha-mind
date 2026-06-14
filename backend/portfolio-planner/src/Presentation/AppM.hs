{-# LANGUAGE GeneralizedNewtypeDeriving #-}

{- | Application monad for the portfolio-planner service.

 'AppM' is a flat @ReaderT AppEnv IO@ that provides all port instances
 required by 'proposeOrders':

   * 'OrderProposalRepository'    → FirestoreOrderProposalRepositoryT
   * 'ProposalDispatchRepository' → FirestoreProposalDispatchRepositoryT
   * 'IdempotencyKeyRepository'   → FirestoreIdempotencyRepositoryT

 The PubSub publisher is not a typeclass; it is called directly from the
 handler via 'runPubSubPortfolioEventPublisherT'.
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
import Data.Text (Text)
import Domain.OrderProposal.Ports (
  IdempotencyKeyRepository (..),
  OrderProposalRepository (..),
  ProposalDispatchRepository (..),
 )
import Domain.OrderProposal.Ports qualified as IdempotencyPorts
import Domain.OrderProposal.Ports qualified as OrderProposalPorts
import Domain.OrderProposal.Ports qualified as ProposalDispatchPorts
import Infrastructure.Publisher.PubSubPortfolioEventPublisher (
  PubSubPortfolioEventPublisherEnv (..),
 )
import Infrastructure.Repository.FirestoreIdempotencyRepository (
  FirestoreIdempotencyEnv (..),
  runFirestoreIdempotencyRepositoryT,
 )
import Infrastructure.Repository.FirestoreOrderProposalRepository (
  FirestoreOrderProposalEnv (..),
  runFirestoreOrderProposalRepositoryT,
 )
import Infrastructure.Repository.FirestoreProposalDispatchRepository (
  FirestoreProposalDispatchEnv (..),
  runFirestoreProposalDispatchRepositoryT,
 )
import Messaging.PubSub (PubSubPublisher (..))
import Network.HTTP.Client.TLS (newTlsManager)
import Observability.Logging (LogEnv, initLogger)
import Persistence.Firestore (FirestoreContext (..))

-- ---------------------------------------------------------------------------
-- Application environment
-- ---------------------------------------------------------------------------

data AppEnv = AppEnv
  { firestoreContext :: FirestoreContext
  , logEnv :: LogEnv
  , pubSubEnv :: PubSubPortfolioEventPublisherEnv
  , serviceName :: Text
  }

-- ---------------------------------------------------------------------------
-- Application monad
-- ---------------------------------------------------------------------------

newtype AppM a = AppM {unAppM :: ReaderT AppEnv IO a}
  deriving newtype (Functor, Applicative, Monad, MonadIO)

runAppM :: AppEnv -> AppM a -> IO a
runAppM appEnv action = runReaderT (unAppM action) appEnv

-- ---------------------------------------------------------------------------
-- OrderProposalRepository instance
-- Delegates to FirestoreOrderProposalRepositoryT.
-- ---------------------------------------------------------------------------

instance OrderProposalRepository AppM where
  findOrderProposal proposalIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreOrderProposalEnv{firestoreContext = appEnv.firestoreContext}
        action = OrderProposalPorts.findOrderProposal proposalIdentifier
    liftIO $ runFirestoreOrderProposalRepositoryT firestoreEnv action

  findOrderProposalsByStatus statusValue = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreOrderProposalEnv{firestoreContext = appEnv.firestoreContext}
        action = OrderProposalPorts.findOrderProposalsByStatus statusValue
    liftIO $ runFirestoreOrderProposalRepositoryT firestoreEnv action

  searchOrderProposals criteria = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreOrderProposalEnv{firestoreContext = appEnv.firestoreContext}
        action = OrderProposalPorts.searchOrderProposals criteria
    liftIO $ runFirestoreOrderProposalRepositoryT firestoreEnv action

  persistOrderProposal proposal = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreOrderProposalEnv{firestoreContext = appEnv.firestoreContext}
        action = OrderProposalPorts.persistOrderProposal proposal
    liftIO $ runFirestoreOrderProposalRepositoryT firestoreEnv action

  terminateOrderProposal proposalIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreOrderProposalEnv{firestoreContext = appEnv.firestoreContext}
        action = OrderProposalPorts.terminateOrderProposal proposalIdentifier
    liftIO $ runFirestoreOrderProposalRepositoryT firestoreEnv action

-- ---------------------------------------------------------------------------
-- ProposalDispatchRepository instance
-- Delegates to FirestoreProposalDispatchRepositoryT.
-- ---------------------------------------------------------------------------

instance ProposalDispatchRepository AppM where
  findProposalDispatch dispatchIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreProposalDispatchEnv{firestoreContext = appEnv.firestoreContext}
        action = ProposalDispatchPorts.findProposalDispatch dispatchIdentifier
    liftIO $ runFirestoreProposalDispatchRepositoryT firestoreEnv action

  persistProposalDispatch dispatch = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreProposalDispatchEnv{firestoreContext = appEnv.firestoreContext}
        action = ProposalDispatchPorts.persistProposalDispatch dispatch
    liftIO $ runFirestoreProposalDispatchRepositoryT firestoreEnv action

  terminateProposalDispatch dispatchIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreProposalDispatchEnv{firestoreContext = appEnv.firestoreContext}
        action = ProposalDispatchPorts.terminateProposalDispatch dispatchIdentifier
    liftIO $ runFirestoreProposalDispatchRepositoryT firestoreEnv action

-- ---------------------------------------------------------------------------
-- IdempotencyKeyRepository instance
-- Delegates to FirestoreIdempotencyRepositoryT.
-- ---------------------------------------------------------------------------

instance IdempotencyKeyRepository AppM where
  findIdempotencyKey dispatchIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreIdempotencyEnv{firestoreContext = appEnv.firestoreContext}
        action = IdempotencyPorts.findIdempotencyKey dispatchIdentifier
    liftIO $ runFirestoreIdempotencyRepositoryT firestoreEnv action

  persistIdempotencyKey dispatch = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreIdempotencyEnv{firestoreContext = appEnv.firestoreContext}
        action = IdempotencyPorts.persistIdempotencyKey dispatch
    liftIO $ runFirestoreIdempotencyRepositoryT firestoreEnv action

  terminateIdempotencyKey dispatchIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreIdempotencyEnv{firestoreContext = appEnv.firestoreContext}
        action = IdempotencyPorts.terminateIdempotencyKey dispatchIdentifier
    liftIO $ runFirestoreIdempotencyRepositoryT firestoreEnv action

-- ---------------------------------------------------------------------------
-- Environment construction
-- ---------------------------------------------------------------------------

{- | Build 'AppEnv' from environment variables.
 Required:
   GCP_PROJECT_ID (or GOOGLE_CLOUD_PROJECT) — via loadCommonRuntimeEnv
   PUBSUB_ORDERS_PROPOSED_TOPIC             — proposedTopicName
   PUBSUB_ORDERS_PROPOSAL_FAILED_TOPIC      — failedTopicName
 Optional:
   FIRESTORE_DATABASE_ID (default "(default)")
-}
buildAppEnv :: IO AppEnv
buildAppEnv = do
  runtimeEnv <- loadCommonRuntimeEnv "portfolio-planner"
  logEnvironment <- initLogger runtimeEnv
  let projectIdentifier :: Text
      projectIdentifier = runtimeEnv.gcpProjectId

  -- Pub/Sub
  proposedTopicNameValue <- requireTextEnv "PUBSUB_ORDERS_PROPOSED_TOPIC"
  failedTopicNameValue <- requireTextEnv "PUBSUB_ORDERS_PROPOSAL_FAILED_TOPIC"
  httpManager <- newTlsManager
  let pubSubPublisher =
        PubSubPublisher
          { manager = httpManager
          , projectId = projectIdentifier
          , baseURL = "https://pubsub.googleapis.com/v1/"
          , accessToken = pure ""
          }
      pubSubEnvironment =
        PubSubPortfolioEventPublisherEnv
          { publisher = pubSubPublisher
          , proposedTopicName = proposedTopicNameValue
          , failedTopicName = failedTopicNameValue
          }

  -- Firestore
  maybeDatabaseIdentifier <- optionalTextEnv "FIRESTORE_DATABASE_ID"
  let databaseIdentifier = fromMaybe "(default)" maybeDatabaseIdentifier
      firestoreCtx =
        FirestoreContext
          { projectId = projectIdentifier
          , databaseId = databaseIdentifier
          }

  pure
    AppEnv
      { firestoreContext = firestoreCtx
      , logEnv = logEnvironment
      , pubSubEnv = pubSubEnvironment
      , serviceName = "portfolio-planner"
      }
