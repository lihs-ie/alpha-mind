{-# LANGUAGE GeneralizedNewtypeDeriving #-}

{- | Application monad for the insight-collector service.

 'AppM' is a flat @ReaderT AppEnv IO@ that provides all eight port instances
 required by 'collectInsights':

   * 'InsightDispatchRepository'        → STUB: no infrastructure implementation yet
   * 'InsightCollectionRepository'      → FirestoreInsightCollectionRepositoryT
   * 'SourcePolicyRepository'           → FirestoreSourcePolicyRepositoryT
   * 'InsightRecordRepository'          → FirestoreInsightRecordRepositoryT
   * 'InsightArtifactRepository'        → STUB: no infrastructure implementation yet
   * 'ExternalSourcePort'               → XExternalSourceT / YouTubeExternalSourceT /
                                           PaperExternalSourceT / GitHubExternalSourceT
   * 'InsightCollectionEventPublisher'  → PubSubInsightEventPublisherT
   * 'InsightAuditPort'                 → inline logInfoWith (Observability.Logging)
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

import ACL.ExternalSource.GitHub (GitHubEnv (..), runGitHubExternalSourceT)
import ACL.ExternalSource.Paper (PaperEnv (..), runPaperExternalSourceT)
import ACL.ExternalSource.X (XEnv (..), runXExternalSourceT)
import ACL.ExternalSource.YouTube (YouTubeEnv (..), runYouTubeExternalSourceT)
import Config.Env (CommonRuntimeEnv (..), loadCommonRuntimeEnv, optionalTextEnv, requireTextEnv)
import Control.Monad.IO.Class (MonadIO (liftIO))
import Control.Monad.Trans.Reader (ReaderT (..), ask, runReaderT)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (
  InsightArtifactRepository (..),
  InsightCollectionIdentifier (..),
  InsightCollectionRepository (..),
  InsightRecordRepository (..),
  SourcePolicyRepository (..),
  SourcePolicySnapshot (..),
  SourceType (..),
 )
import Domain.InsightCollection.ExternalSourcePort (ExternalSourcePort (..))
import Domain.InsightCollection.InsightDispatch (InsightDispatchRepository (..))
import Infrastructure.Publisher.PubSubInsightEventPublisher (
  PubSubInsightEventPublisherEnv (..),
  runPubSubInsightEventPublisherT,
 )
import Infrastructure.Repository.FirestoreInsightCollectionRepository (
  FirestoreInsightCollectionEnv (..),
  runFirestoreInsightCollectionRepositoryT,
 )
import Infrastructure.Repository.FirestoreInsightRecordRepository (
  FirestoreInsightRecordEnv (..),
  runFirestoreInsightRecordRepositoryT,
 )
import Infrastructure.Repository.FirestoreSourcePolicyRepository (
  FirestoreSourcePolicyEnv (..),
  runFirestoreSourcePolicyRepositoryT,
 )
import Messaging.PubSub (PubSubPublisher (..))
import Network.HTTP.Client (httpLbs)
import Network.HTTP.Client.TLS (newTlsManager)
import Observability.Logging (LogContext (..), LogEnv, initLogger, logInfoWith)
import Persistence.Firestore (FirestoreContext (..))
import UseCase.CollectInsights (InsightCollectionEventPublisher (..))
import UseCase.RecordInsightAudit (InsightAuditPort (..))

-- ---------------------------------------------------------------------------
-- Application environment
-- ---------------------------------------------------------------------------

data AppEnv = AppEnv
  { firestoreContext :: FirestoreContext
  , logEnv :: LogEnv
  , pubSubEnv :: PubSubInsightEventPublisherEnv
  , xEnv :: XEnv
  , youTubeEnv :: YouTubeEnv
  , paperEnv :: PaperEnv
  , gitHubEnv :: GitHubEnv
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
-- InsightDispatchRepository instance
-- STUB: no infrastructure implementation yet
-- ---------------------------------------------------------------------------

instance InsightDispatchRepository AppM where
  -- STUB: no infrastructure implementation yet
  findDispatch _collectionIdentifier = liftIO (pure Nothing)

  -- STUB: no infrastructure implementation yet
  persistDispatch _dispatch = liftIO (pure ())

  -- STUB: no infrastructure implementation yet
  terminateDispatch' _collectionIdentifier = liftIO (pure ())

-- ---------------------------------------------------------------------------
-- InsightCollectionRepository instance
-- Delegates to FirestoreInsightCollectionRepositoryT.
-- ---------------------------------------------------------------------------

instance InsightCollectionRepository AppM where
  findCollection collectionIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreInsightCollectionEnv{firestoreContext = appEnv.firestoreContext}
        action = findCollection collectionIdentifier
    liftIO $ runFirestoreInsightCollectionRepositoryT firestoreEnv action

  findByStatus statusValue = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreInsightCollectionEnv{firestoreContext = appEnv.firestoreContext}
        action = findByStatus statusValue
    liftIO $ runFirestoreInsightCollectionRepositoryT firestoreEnv action

  searchCollections criteria = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreInsightCollectionEnv{firestoreContext = appEnv.firestoreContext}
        action = searchCollections criteria
    liftIO $ runFirestoreInsightCollectionRepositoryT firestoreEnv action

  persistCollection collection = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreInsightCollectionEnv{firestoreContext = appEnv.firestoreContext}
        action = persistCollection collection
    liftIO $ runFirestoreInsightCollectionRepositoryT firestoreEnv action

  terminateCollectionRecord collectionIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreInsightCollectionEnv{firestoreContext = appEnv.firestoreContext}
        action = terminateCollectionRecord collectionIdentifier
    liftIO $ runFirestoreInsightCollectionRepositoryT firestoreEnv action

-- ---------------------------------------------------------------------------
-- SourcePolicyRepository instance
-- Delegates to FirestoreSourcePolicyRepositoryT.
-- ---------------------------------------------------------------------------

instance SourcePolicyRepository AppM where
  searchPolicies sourceTypes = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreSourcePolicyEnv{firestoreContext = appEnv.firestoreContext}
        action = searchPolicies sourceTypes
    liftIO $ runFirestoreSourcePolicyRepositoryT firestoreEnv action

  findBySourceType sourceTypeValue = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreSourcePolicyEnv{firestoreContext = appEnv.firestoreContext}
        action = findBySourceType sourceTypeValue
    liftIO $ runFirestoreSourcePolicyRepositoryT firestoreEnv action

-- ---------------------------------------------------------------------------
-- InsightRecordRepository instance
-- Delegates to FirestoreInsightRecordRepositoryT.
-- ---------------------------------------------------------------------------

instance InsightRecordRepository AppM where
  persistRecord insightRecord = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreInsightRecordEnv{firestoreContext = appEnv.firestoreContext}
        action = persistRecord insightRecord
    liftIO $ runFirestoreInsightRecordRepositoryT firestoreEnv action

  searchRecords targetDate sourceTypes = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreInsightRecordEnv{firestoreContext = appEnv.firestoreContext}
        action = searchRecords targetDate sourceTypes
    liftIO $ runFirestoreInsightRecordRepositoryT firestoreEnv action

  findByTargetDate targetDate = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreInsightRecordEnv{firestoreContext = appEnv.firestoreContext}
        action = findByTargetDate targetDate
    liftIO $ runFirestoreInsightRecordRepositoryT firestoreEnv action

-- ---------------------------------------------------------------------------
-- InsightArtifactRepository instance
-- STUB: no infrastructure implementation yet
-- ---------------------------------------------------------------------------

instance InsightArtifactRepository AppM where
  -- STUB: no infrastructure implementation yet
  persistArtifact _artifact = liftIO (pure ())

  -- STUB: no infrastructure implementation yet
  findArtifact _collectionIdentifier = liftIO (pure Nothing)

  -- STUB: no infrastructure implementation yet
  terminateArtifact _collectionIdentifier = liftIO (pure ())

-- ---------------------------------------------------------------------------
-- ExternalSourcePort instance
-- Dispatches on SourcePolicySnapshot.sourceType.
-- ---------------------------------------------------------------------------

instance ExternalSourcePort AppM where
  fetchInsights policy targetDate = AppM $ do
    appEnv <- ask
    case policy.sourceType of
      X ->
        liftIO $ runXExternalSourceT appEnv.xEnv (fetchInsights policy targetDate)
      YouTube ->
        liftIO $ runYouTubeExternalSourceT appEnv.youTubeEnv (fetchInsights policy targetDate)
      Paper ->
        liftIO $ runPaperExternalSourceT appEnv.paperEnv (fetchInsights policy targetDate)
      GitHub ->
        liftIO $ runGitHubExternalSourceT appEnv.gitHubEnv (fetchInsights policy targetDate)

-- ---------------------------------------------------------------------------
-- InsightCollectionEventPublisher instance
-- Delegates to PubSubInsightEventPublisherT.
-- ---------------------------------------------------------------------------

instance InsightCollectionEventPublisher AppM where
  publishInsightCollected collectionIdentifier artifact traceValue = AppM $ do
    appEnv <- ask
    let pubSubEnvironment = appEnv.pubSubEnv
        action = publishInsightCollected collectionIdentifier artifact traceValue
    liftIO $ runPubSubInsightEventPublisherT pubSubEnvironment action

  publishInsightCollectFailed collectionIdentifier reasonCodeValue maybeDetail traceValue = AppM $ do
    appEnv <- ask
    let pubSubEnvironment = appEnv.pubSubEnv
        action = publishInsightCollectFailed collectionIdentifier reasonCodeValue maybeDetail traceValue
    liftIO $ runPubSubInsightEventPublisherT pubSubEnvironment action

-- ---------------------------------------------------------------------------
-- InsightAuditPort instance
-- Inline logInfoWith call using Observability.Logging.
-- ---------------------------------------------------------------------------

instance InsightAuditPort AppM where
  writeInsightAudit collectionIdentifier traceValue _entry = AppM $ do
    appEnv <- ask
    let Trace traceUlid = traceValue
        InsightCollectionIdentifier identifierUlid = collectionIdentifier
        logContext =
          LogContext
            { service = "insight-collector"
            , trace = Just (Text.pack (show traceUlid))
            , identifier = Just (Text.pack (show identifierUlid))
            , eventType = Just "insight_audit"
            , reasonCode = Nothing
            , result = Nothing
            , payloadSummary = Nothing
            }
    liftIO $ logInfoWith appEnv.logEnv logContext "insight_audit_recorded"

-- ---------------------------------------------------------------------------
-- Environment construction
-- ---------------------------------------------------------------------------

{- | Build 'AppEnv' from environment variables.
 Required variables:
   GCP_PROJECT_ID (or GOOGLE_CLOUD_PROJECT) — via loadCommonRuntimeEnv
   SERVICE_VERSION                           — via loadCommonRuntimeEnv
   PUBSUB_INSIGHT_COLLECTED_TOPIC
   PUBSUB_INSIGHT_COLLECT_FAILED_TOPIC
   X_API_BEARER_TOKEN
   YOUTUBE_API_KEY
   GITHUB_PERSONAL_ACCESS_TOKEN
 Optional:
   FIRESTORE_DATABASE_ID (default "(default)")
   INSIGHT_SKILL_VERSION (default "v1.0.0")
-}
buildAppEnv :: IO AppEnv
buildAppEnv = do
  runtimeEnv <- loadCommonRuntimeEnv "insight-collector"
  logEnvironment <- initLogger runtimeEnv
  let projectIdentifier = runtimeEnv.gcpProjectId

  -- Pub/Sub
  collectedTopicNameValue <- requireTextEnv "PUBSUB_INSIGHT_COLLECTED_TOPIC"
  failedTopicNameValue <- requireTextEnv "PUBSUB_INSIGHT_COLLECT_FAILED_TOPIC"
  httpManager <- newTlsManager
  let pubSubPublisher =
        PubSubPublisher
          { manager = httpManager
          , projectId = projectIdentifier
          , baseURL = "https://pubsub.googleapis.com/v1/"
          , accessToken = pure ""
          }
      pubSubEnvironment =
        PubSubInsightEventPublisherEnv
          { publisher = pubSubPublisher
          , collectedTopicName = collectedTopicNameValue
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

  -- Skill version
  maybeSkillVersion <- optionalTextEnv "INSIGHT_SKILL_VERSION"
  let skillVersionValue = fromMaybe "v1.0.0" maybeSkillVersion

  -- HTTP manager for ACL adapters
  httpManagerForAcl <- newTlsManager
  let executeHttpWithManager = (`httpLbs` httpManagerForAcl)

  -- X ACL
  xApiBearerToken <- requireTextEnv "X_API_BEARER_TOKEN"
  let xEnvironment =
        XEnv
          { bearerToken = xApiBearerToken
          , accountHandles = []
          , timeoutSeconds = 30
          , skillVersion = skillVersionValue
          , httpExecute = executeHttpWithManager
          }

  -- YouTube ACL
  youTubeApiKey <- requireTextEnv "YOUTUBE_API_KEY"
  let youTubeEnvironment =
        YouTubeEnv
          { apiKey = youTubeApiKey
          , timeoutSeconds = 30
          , skillVersion = skillVersionValue
          , httpExecute = executeHttpWithManager
          }

  -- Paper ACL
  let paperEnvironment =
        PaperEnv
          { timeoutSeconds = 30
          , skillVersion = skillVersionValue
          , httpExecute = executeHttpWithManager
          }

  -- GitHub ACL
  gitHubPersonalAccessToken <- requireTextEnv "GITHUB_PERSONAL_ACCESS_TOKEN"
  let gitHubEnvironment =
        GitHubEnv
          { personalAccessToken = gitHubPersonalAccessToken
          , timeoutSeconds = 30
          , skillVersion = skillVersionValue
          , httpExecute = executeHttpWithManager
          }

  pure
    AppEnv
      { firestoreContext = firestoreCtx
      , logEnv = logEnvironment
      , pubSubEnv = pubSubEnvironment
      , xEnv = xEnvironment
      , youTubeEnv = youTubeEnvironment
      , paperEnv = paperEnvironment
      , gitHubEnv = gitHubEnvironment
      , serviceName = "insight-collector"
      }
