{-# LANGUAGE GeneralizedNewtypeDeriving #-}

{- | Application monad for the risk-guard service.

 'AppM' is a flat @ReaderT AppEnv IO@ that provides all three port instances
 required by 'checkOrderRisk' and 'syncKillSwitch':

   * 'OrderRiskAssessmentRepository' → FirestoreRiskAssessmentRepositoryT
   * 'IdempotencyKeyRepository'      → FirestoreIdempotencyKeyRepositoryT
   * 'RiskEventPublisher'            → PubSubRiskEventPublisherT

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

  -- * Settings loader (for presentation layer — avoids direct infra imports)
  loadSettings,
) where

import Config.Env (CommonRuntimeEnv (..), loadCommonRuntimeEnv, optionalTextEnv, requireTextEnv)
import Control.Monad.IO.Class (MonadIO (liftIO))
import Control.Monad.Trans.Reader (ReaderT (..), ask, runReaderT)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Domain.RiskAssessment.Aggregate (
  OrderRiskAssessmentRepository (..),
  RiskEventPublisher (..),
 )
import Domain.RiskAssessment.Aggregate qualified as AssessmentRepository
import Domain.RiskAssessment.Port.IdempotencyKeyRepository (IdempotencyKeyRepository (..))
import Domain.RiskAssessment.Port.IdempotencyKeyRepository qualified as IdempotencyRepository
import Domain.RiskAssessment.ValueObjects (CompliancePolicy, RiskExposure, RiskLimits)
import Infrastructure.Publisher.PubSubRiskEventPublisher (
  PubSubRiskEventPublisherEnv (..),
  runPubSubRiskEventPublisherT,
 )
import Infrastructure.Repository.FirestoreIdempotencyKeyRepository (
  FirestoreIdempotencyKeyEnv (..),
  runFirestoreIdempotencyKeyRepositoryT,
 )
import Infrastructure.Repository.FirestoreKillSwitchStateRepository (FirestoreKillSwitchStateEnv (..))
import Infrastructure.Repository.FirestoreRiskAssessmentRepository (
  FirestoreRiskAssessmentEnv (..),
  runFirestoreRiskAssessmentRepositoryT,
 )
import Infrastructure.Repository.FirestoreRiskSettingsRepository (
  FirestoreRiskSettingsEnv (..),
  loadCompliancePolicy,
  loadKillSwitchState,
  loadRiskExposure,
  loadRiskLimits,
 )
import Messaging.PubSub (PubSubPublisher (..))
import Network.HTTP.Client.TLS (newTlsManager)
import Persistence.Firestore (FirestoreContext (..))

-- ---------------------------------------------------------------------------
-- Application environment
-- ---------------------------------------------------------------------------

-- | AppEnv holds all sub-environments needed to run the risk-guard service.
data AppEnv = AppEnv
  { assessmentEnv :: FirestoreRiskAssessmentEnv
  , idempotencyEnv :: FirestoreIdempotencyKeyEnv
  , settingsEnv :: FirestoreRiskSettingsEnv
  , killSwitchEnv :: FirestoreKillSwitchStateEnv
  , publisherEnv :: PubSubRiskEventPublisherEnv
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
-- OrderRiskAssessmentRepository instance
-- Delegates to FirestoreRiskAssessmentRepositoryT.
-- ---------------------------------------------------------------------------

instance OrderRiskAssessmentRepository AppM where
  find assessmentIdentifier = AppM $ do
    appEnv <- ask
    let action = AssessmentRepository.find assessmentIdentifier
    liftIO $ runFirestoreRiskAssessmentRepositoryT appEnv.assessmentEnv action

  findByStatus statusValue = AppM $ do
    appEnv <- ask
    let action = AssessmentRepository.findByStatus statusValue
    liftIO $ runFirestoreRiskAssessmentRepositoryT appEnv.assessmentEnv action

  search criteria = AppM $ do
    appEnv <- ask
    let action = AssessmentRepository.search criteria
    liftIO $ runFirestoreRiskAssessmentRepositoryT appEnv.assessmentEnv action

  persist assessment = AppM $ do
    appEnv <- ask
    let action = AssessmentRepository.persist assessment
    liftIO $ runFirestoreRiskAssessmentRepositoryT appEnv.assessmentEnv action

  terminate assessmentIdentifier = AppM $ do
    appEnv <- ask
    let action = AssessmentRepository.terminate assessmentIdentifier
    liftIO $ runFirestoreRiskAssessmentRepositoryT appEnv.assessmentEnv action

-- ---------------------------------------------------------------------------
-- IdempotencyKeyRepository instance
-- Delegates to FirestoreIdempotencyKeyRepositoryT.
-- ---------------------------------------------------------------------------

instance IdempotencyKeyRepository AppM where
  find serviceText eventKeyText = AppM $ do
    appEnv <- ask
    let action = IdempotencyRepository.find serviceText eventKeyText
    liftIO $ runFirestoreIdempotencyKeyRepositoryT appEnv.idempotencyEnv action

  persist serviceText eventKeyText = AppM $ do
    appEnv <- ask
    let action = IdempotencyRepository.persist serviceText eventKeyText
    liftIO $ runFirestoreIdempotencyKeyRepositoryT appEnv.idempotencyEnv action

  terminate serviceText eventKeyText = AppM $ do
    appEnv <- ask
    let action = IdempotencyRepository.terminate serviceText eventKeyText
    liftIO $ runFirestoreIdempotencyKeyRepositoryT appEnv.idempotencyEnv action

-- ---------------------------------------------------------------------------
-- RiskEventPublisher instance
-- Delegates to PubSubRiskEventPublisherT.
-- ---------------------------------------------------------------------------

instance RiskEventPublisher AppM where
  publishOrdersApproved approvedPayload = AppM $ do
    appEnv <- ask
    liftIO $ runPubSubRiskEventPublisherT appEnv.publisherEnv (publishOrdersApproved approvedPayload)

  publishOrdersRejected rejectedPayload = AppM $ do
    appEnv <- ask
    liftIO $ runPubSubRiskEventPublisherT appEnv.publisherEnv (publishOrdersRejected rejectedPayload)

-- ---------------------------------------------------------------------------
-- Environment construction (Must-09)
-- ---------------------------------------------------------------------------

{- | Must-09: Build 'AppEnv' from environment variables.

 Required (via loadCommonRuntimeEnv):
   GCP_PROJECT_ID (or GOOGLE_CLOUD_PROJECT) — GCP project ID for both Firestore and Pub/Sub
   SERVICE_VERSION                           — service version string

 Required:
   ORDERS_APPROVED_TOPIC         — orders.approved topic name
   ORDERS_REJECTED_TOPIC         — orders.rejected topic name

 Optional:
   FIRESTORE_PROJECT_ID   — override GCP project ID for Firestore
   PUBSUB_PROJECT_ID      — override GCP project ID for Pub/Sub
   FIRESTORE_DATABASE_ID  — Firestore database ID (default "(default)")
-}
buildAppEnv :: IO AppEnv
buildAppEnv = do
  commonEnv <- loadCommonRuntimeEnv "risk-guard"
  let gcpProjectId = commonEnv.gcpProjectId

  -- Firestore project: prefer explicit override, fall back to GCP_PROJECT_ID
  maybeFirestoreProjectIdentifier <- optionalTextEnv "FIRESTORE_PROJECT_ID"
  let firestoreProjectIdentifier = fromMaybe gcpProjectId maybeFirestoreProjectIdentifier
  maybeDatabaseIdentifier <- optionalTextEnv "FIRESTORE_DATABASE_ID"
  let databaseIdentifier = fromMaybe "(default)" maybeDatabaseIdentifier
      firestoreCtx =
        FirestoreContext
          { projectId = firestoreProjectIdentifier
          , databaseId = databaseIdentifier
          }
      assessmentEnvironment = FirestoreRiskAssessmentEnv{firestoreContext = firestoreCtx}
      idempotencyEnvironment = FirestoreIdempotencyKeyEnv{firestoreContext = firestoreCtx}
      settingsEnvironment = FirestoreRiskSettingsEnv{firestoreContext = firestoreCtx}
      killSwitchEnvironment = FirestoreKillSwitchStateEnv{firestoreContext = firestoreCtx}

  -- Pub/Sub project: prefer explicit override, fall back to GCP_PROJECT_ID
  maybePubSubProjectIdentifier <- optionalTextEnv "PUBSUB_PROJECT_ID"
  let pubSubProjectIdentifier = fromMaybe gcpProjectId maybePubSubProjectIdentifier
  approvedTopicNameValue <- requireTextEnv "ORDERS_APPROVED_TOPIC"
  rejectedTopicNameValue <- requireTextEnv "ORDERS_REJECTED_TOPIC"
  httpManager <- newTlsManager
  let publisher =
        PubSubPublisher
          { manager = httpManager
          , projectId = pubSubProjectIdentifier
          , baseURL = "https://pubsub.googleapis.com/v1/"
          , accessToken = pure ""
          }
      publisherEnvironment =
        PubSubRiskEventPublisherEnv
          { publisher = publisher
          , approvedTopicName = approvedTopicNameValue
          , rejectedTopicName = rejectedTopicNameValue
          }

  pure
    AppEnv
      { assessmentEnv = assessmentEnvironment
      , idempotencyEnv = idempotencyEnvironment
      , settingsEnv = settingsEnvironment
      , killSwitchEnv = killSwitchEnvironment
      , publisherEnv = publisherEnvironment
      , serviceName = "risk-guard"
      }

-- ---------------------------------------------------------------------------
-- Settings loader (for presentation layer — avoids direct infra imports)
-- ---------------------------------------------------------------------------

{- | Load risk settings from Firestore using the settings environment in 'AppEnv'.

 This function is provided so that presentation-layer modules can load settings
 without directly importing 'Infrastructure.Repository.FirestoreRiskSettingsRepository'.
-}
loadSettings :: AppEnv -> IO (Bool, RiskLimits, CompliancePolicy, RiskExposure)
loadSettings appEnv = do
  killSwitchEnabled <- loadKillSwitchState appEnv.settingsEnv
  riskLimits <- loadRiskLimits appEnv.settingsEnv
  compliancePolicy <- loadCompliancePolicy appEnv.settingsEnv
  riskExposure <- loadRiskExposure appEnv.settingsEnv
  pure (killSwitchEnabled, riskLimits, compliancePolicy, riskExposure)
