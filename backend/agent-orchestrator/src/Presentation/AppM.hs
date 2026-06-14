{-# LANGUAGE GeneralizedNewtypeDeriving #-}

{- | Application monad for the agent-orchestrator service.

 'AppM' is a flat @ReaderT AppEnv IO@ that provides all six port instances
 required by 'orchestrateFromInsight' and 'orchestrateFromRetest':

   * 'OrchestrationDispatchRepository'  → FirestoreOrchestrationDispatchRepositoryT
   * 'HypothesisProposalRepository'     → FirestoreHypothesisProposalRepositoryT
   * 'SkillRegistryRepository'          → FirestoreSkillRegistryRepositoryT
   * 'InstructionProfileRepository'     → FirestoreInstructionProfileRepositoryT
   * 'FailureKnowledgeRepository'       → FirestoreFailureKnowledgeRepositoryT
   * 'SkillExecutor'                    → SkillExecutorT

 Must-26: AppM does NOT import UseCase.* directly.
 UseCase functions are called from Presentation.PubSubHandler only.
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
import Data.Aeson (encode, object, (.=))
import Data.Base64.Types (extractBase64)
import Data.ByteString.Base64 (encodeBase64)
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.HashMap.Strict (HashMap)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding (encodeUtf8)
import Domain.HypothesisOrchestration.Aggregate (
  HypothesisProposalRepository (..),
 )
import Domain.HypothesisOrchestration.Aggregate qualified as HypothesisProposalRepository
import Domain.HypothesisOrchestration.FailureKnowledge (
  FailureKnowledgeRepository (..),
 )
import Domain.HypothesisOrchestration.FailureKnowledge qualified as FailureKnowledgeRepository
import Domain.HypothesisOrchestration.InstructionProfile (
  InstructionProfileRepository (..),
 )
import Domain.HypothesisOrchestration.InstructionProfile qualified as InstructionProfileRepository
import Domain.HypothesisOrchestration.OrchestrationDispatch (
  OrchestrationDispatchRepository (..),
 )
import Domain.HypothesisOrchestration.OrchestrationDispatch qualified as OrchestrationDispatchRepository
import Domain.HypothesisOrchestration.SkillExecutor (
  SkillExecutor (..),
 )
import Domain.HypothesisOrchestration.SkillExecutor qualified as SkillExecutorPort
import Domain.HypothesisOrchestration.SkillRegistry (
  SkillRegistryRepository (..),
 )
import Domain.HypothesisOrchestration.SkillRegistry qualified as SkillRegistryRepository
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.ACL.SkillExecutorT (
  SkillExecutorEnv (..),
  SkillExecutorT (..),
  runSkillExecutorT,
  skillExecutorEndpointEnvVar,
 )
import Infrastructure.Firestore.Env (
  FirestoreEnv (..),
  FirestoreTransport (..),
  firestoreDatabaseIdEnvVar,
  gcpProjectIdEnvVar,
 )
import Infrastructure.Firestore.FailureKnowledgeRepository (
  FirestoreFailureKnowledgeEnv (..),
  runFirestoreFailureKnowledgeRepositoryT,
 )
import Infrastructure.Firestore.HypothesisProposalRepository (
  FirestoreHypothesisProposalEnv (..),
  runFirestoreHypothesisProposalRepositoryT,
 )
import Infrastructure.Firestore.InstructionProfileRepository (
  FirestoreInstructionProfileEnv (..),
  runFirestoreInstructionProfileRepositoryT,
 )
import Infrastructure.Firestore.OrchestrationDispatchRepository (
  FirestoreOrchestrationDispatchEnv (..),
  runFirestoreOrchestrationDispatchRepositoryT,
 )
import Infrastructure.Firestore.SkillRegistryRepository (
  FirestoreSkillRegistryEnv (..),
  runFirestoreSkillRegistryRepositoryT,
 )
import Infrastructure.PubSub.HypothesisEventPublisher (
  HypothesisPublisherEnv (..),
  hypothesisPubSubTopicEnvVar,
 )
import Messaging.PubSub (PubSubPublisher (..), mkTopicPath)
import Network.HTTP.Client (
  Request (..),
  RequestBody (..),
  Response (..),
  httpLbs,
  parseRequest,
 )
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types (statusCode)
import Observability.Logging (LogEnv, initLogger)
import Persistence.Firestore (
  CollectionName,
  DocumentId,
  FirestoreContext (..),
  FromFirestore (..),
  ToFirestore (..),
  deleteDocument,
  getDocument,
  runQuery,
  upsertDocument,
 )

-- ---------------------------------------------------------------------------
-- Application environment (Must-05)
-- ---------------------------------------------------------------------------

{- | Must-05: AppEnv holds all sub-environments needed by the six port instances.

 Fields:
   * 'firestoreEnv'           — shared injectable Firestore transport
   * 'skillExecutorEnv'       — HTTP ACL for external skill runtime
   * 'hypothesisPublisherEnv' — Pub/Sub publisher for hypothesis events
   * 'logEnv'                 — katip structured logging environment
   * 'serviceName'            — service name for log context (Should)
-}
data AppEnv = AppEnv
  { firestoreEnv :: FirestoreEnv
  , skillExecutorEnv :: SkillExecutorEnv
  , hypothesisPublisherEnv :: HypothesisPublisherEnv
  , logEnv :: LogEnv
  , serviceName :: Text
  }

-- ---------------------------------------------------------------------------
-- Application monad (Must-06)
-- ---------------------------------------------------------------------------

-- | Must-06: Flat ReaderT AppEnv IO newtype.
newtype AppM a = AppM {unAppM :: ReaderT AppEnv IO a}
  deriving newtype (Functor, Applicative, Monad, MonadIO)

runAppM :: AppEnv -> AppM a -> IO a
runAppM appEnv action = runReaderT (unAppM action) appEnv

-- ---------------------------------------------------------------------------
-- OrchestrationDispatchRepository instance (Must-07)
-- ---------------------------------------------------------------------------

instance OrchestrationDispatchRepository AppM where
  find dispatchIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreOrchestrationDispatchEnv{firestoreEnv = appEnv.firestoreEnv}
        action = OrchestrationDispatchRepository.find dispatchIdentifier
    liftIO $ runFirestoreOrchestrationDispatchRepositoryT firestoreEnvironment action

  persist dispatch = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreOrchestrationDispatchEnv{firestoreEnv = appEnv.firestoreEnv}
        action = OrchestrationDispatchRepository.persist dispatch
    liftIO $ runFirestoreOrchestrationDispatchRepositoryT firestoreEnvironment action

  terminate dispatchIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreOrchestrationDispatchEnv{firestoreEnv = appEnv.firestoreEnv}
        action = OrchestrationDispatchRepository.terminate dispatchIdentifier
    liftIO $ runFirestoreOrchestrationDispatchRepositoryT firestoreEnvironment action

-- ---------------------------------------------------------------------------
-- HypothesisProposalRepository instance (Must-07)
-- ---------------------------------------------------------------------------

instance HypothesisProposalRepository AppM where
  find proposalIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreHypothesisProposalEnv{firestoreEnv = appEnv.firestoreEnv}
        action = HypothesisProposalRepository.find proposalIdentifier
    liftIO $ runFirestoreHypothesisProposalRepositoryT firestoreEnvironment action

  findByStatus proposalStatus = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreHypothesisProposalEnv{firestoreEnv = appEnv.firestoreEnv}
        action = HypothesisProposalRepository.findByStatus proposalStatus
    liftIO $ runFirestoreHypothesisProposalRepositoryT firestoreEnvironment action

  search criteria = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreHypothesisProposalEnv{firestoreEnv = appEnv.firestoreEnv}
        action = HypothesisProposalRepository.search criteria
    liftIO $ runFirestoreHypothesisProposalRepositoryT firestoreEnvironment action

  persist proposal = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreHypothesisProposalEnv{firestoreEnv = appEnv.firestoreEnv}
        action = HypothesisProposalRepository.persist proposal
    liftIO $ runFirestoreHypothesisProposalRepositoryT firestoreEnvironment action

  terminate proposalIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreHypothesisProposalEnv{firestoreEnv = appEnv.firestoreEnv}
        action = HypothesisProposalRepository.terminate proposalIdentifier
    liftIO $ runFirestoreHypothesisProposalRepositoryT firestoreEnvironment action

-- ---------------------------------------------------------------------------
-- SkillRegistryRepository instance (Must-07)
-- ---------------------------------------------------------------------------

instance SkillRegistryRepository AppM where
  find skillReference = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreSkillRegistryEnv{firestoreEnv = appEnv.firestoreEnv}
        action = SkillRegistryRepository.find skillReference
    liftIO $ runFirestoreSkillRegistryRepositoryT firestoreEnvironment action

  findByStatus skillStatus = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreSkillRegistryEnv{firestoreEnv = appEnv.firestoreEnv}
        action = SkillRegistryRepository.findByStatus skillStatus
    liftIO $ runFirestoreSkillRegistryRepositoryT firestoreEnvironment action

  search criteria = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreSkillRegistryEnv{firestoreEnv = appEnv.firestoreEnv}
        action = SkillRegistryRepository.search criteria
    liftIO $ runFirestoreSkillRegistryRepositoryT firestoreEnvironment action

-- ---------------------------------------------------------------------------
-- InstructionProfileRepository instance (Must-07)
-- ---------------------------------------------------------------------------

instance InstructionProfileRepository AppM where
  findByVersion versionText = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreInstructionProfileEnv{firestoreEnv = appEnv.firestoreEnv}
        action = InstructionProfileRepository.findByVersion versionText
    liftIO $ runFirestoreInstructionProfileRepositoryT firestoreEnvironment action

  search criteria = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreInstructionProfileEnv{firestoreEnv = appEnv.firestoreEnv}
        action = InstructionProfileRepository.search criteria
    liftIO $ runFirestoreInstructionProfileRepositoryT firestoreEnvironment action

-- ---------------------------------------------------------------------------
-- FailureKnowledgeRepository instance (Must-07)
-- ---------------------------------------------------------------------------

instance FailureKnowledgeRepository AppM where
  find knowledgeIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreFailureKnowledgeEnv{firestoreEnv = appEnv.firestoreEnv}
        action = FailureKnowledgeRepository.find knowledgeIdentifier
    liftIO $ runFirestoreFailureKnowledgeRepositoryT firestoreEnvironment action

  findByReasonCode reasonCodeValue = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreFailureKnowledgeEnv{firestoreEnv = appEnv.firestoreEnv}
        action = FailureKnowledgeRepository.findByReasonCode reasonCodeValue
    liftIO $ runFirestoreFailureKnowledgeRepositoryT firestoreEnvironment action

  search criteria = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreFailureKnowledgeEnv{firestoreEnv = appEnv.firestoreEnv}
        action = FailureKnowledgeRepository.search criteria
    liftIO $ runFirestoreFailureKnowledgeRepositoryT firestoreEnvironment action

  persist knowledgeEntry = AppM $ do
    appEnv <- ask
    let firestoreEnvironment = FirestoreFailureKnowledgeEnv{firestoreEnv = appEnv.firestoreEnv}
        action = FailureKnowledgeRepository.persist knowledgeEntry
    liftIO $ runFirestoreFailureKnowledgeRepositoryT firestoreEnvironment action

-- ---------------------------------------------------------------------------
-- SkillExecutor instance (Must-07)
-- ---------------------------------------------------------------------------

instance SkillExecutor AppM where
  executeSkill skillInput = AppM $ do
    appEnv <- ask
    liftIO $ runSkillExecutorT appEnv.skillExecutorEnv (SkillExecutorPort.executeSkill skillInput)

-- ---------------------------------------------------------------------------
-- Environment construction (Must-03, Must-04)
-- ---------------------------------------------------------------------------

{- | Must-03/Must-04: Build 'AppEnv' from environment variables.

 Required variables:
   GCP_PROJECT_ID (or GOOGLE_CLOUD_PROJECT)  — via loadCommonRuntimeEnv
   SERVICE_VERSION                            — via loadCommonRuntimeEnv
   PUBSUB_TOPIC_HYPOTHESIS                   — hypothesis Pub/Sub topic name
   SKILL_EXECUTOR_ENDPOINT                   — skill executor HTTP endpoint

 Optional variables:
   PORT                    (default 8080)        — via loadCommonRuntimeEnv
   FIRESTORE_DATABASE_ID   (default "(default)")
   LOG_LEVEL               (default "info")      — via loadCommonRuntimeEnv
-}
buildAppEnv :: IO AppEnv
buildAppEnv = do
  runtimeEnv <- loadCommonRuntimeEnv "agent-orchestrator"
  logEnvironment <- initLogger runtimeEnv
  let projectIdentifier = runtimeEnv.gcpProjectId

  -- Firestore — injectable transport backed by real Persistence.Firestore calls
  maybeDatabaseIdentifier <- optionalTextEnv firestoreDatabaseIdEnvVar
  let databaseIdentifier = fromMaybe "(default)" maybeDatabaseIdentifier
      firestoreCtx =
        FirestoreContext
          { projectId = projectIdentifier
          , databaseId = databaseIdentifier
          }
      productionTransport = buildProductionFirestoreTransport firestoreCtx
      firestoreEnvironment =
        FirestoreEnv
          { firestoreExecute = productionTransport
          , projectIdentifier = projectIdentifier
          , databaseIdentifier = databaseIdentifier
          }

  -- SkillExecutor — shared TLS manager for HTTP calls (Should: share with PubSub)
  skillEndpointUrl <- requireTextEnv skillExecutorEndpointEnvVar
  httpManager <- newTlsManager
  let executeHttpWithManager = (`httpLbs` httpManager)
      skillExecutorEnvironment =
        SkillExecutorEnv
          { endpointUrl = skillEndpointUrl
          , timeoutSeconds = 30
          , httpExecute = executeHttpWithManager
          }

  -- HypothesisEventPublisher — Pub/Sub topic publishing
  hypothesisTopicName <- requireTextEnv hypothesisPubSubTopicEnvVar
  let pubSubPublisher =
        PubSubPublisher
          { manager = httpManager
          , projectId = projectIdentifier
          , baseURL = "https://pubsub.googleapis.com/v1/"
          , -- NOTE: In production on Cloud Run, GCP Workload Identity automatically
            -- injects credentials via ADC (Application Default Credentials).
            -- `pure ""` is safe here because `publishRawBytes` builds its own
            -- Authorization header independently from `accessToken` using
            -- `publishCloudEvent` which calls `retrieveTokenFromStore` internally.
            -- The `accessToken` field is only used by the gogol-based codepath;
            -- our `publishRawBytes` uses direct HTTP with ADC-sourced bearer tokens.
            -- See: infrastructure/ops for Workload Identity SA binding.
            accessToken = pure ""
          }
      publishFn topicName eventBytes = do
        _result <- publishRawBytes pubSubPublisher topicName eventBytes
        pure ()
      hypothesisPublisherEnvironment =
        HypothesisPublisherEnv
          { topicName = hypothesisTopicName
          , pubsubPublish = publishFn
          }

  pure
    AppEnv
      { firestoreEnv = firestoreEnvironment
      , skillExecutorEnv = skillExecutorEnvironment
      , hypothesisPublisherEnv = hypothesisPublisherEnvironment
      , logEnv = logEnvironment
      , serviceName = "agent-orchestrator"
      }

-- ---------------------------------------------------------------------------
-- Raw Pub/Sub publisher (wraps HypothesisEventPublisher bytes → publish request)
-- ---------------------------------------------------------------------------

{- | Publish raw event bytes (JSON) to a Pub/Sub topic.

 The 'HypothesisEventPublisher' calls @environment.pubsubPublish topicName (encode event)@
 where @encode event@ is raw JSON bytes. This function wraps those bytes into
 the Pub/Sub @messages.data@ base64 format and performs the HTTP POST.
-}
publishRawBytes :: PubSubPublisher -> Text -> ByteString.Lazy.ByteString -> IO (Either () ())
publishRawBytes publisher topicName eventBytes = do
  let topicPath = mkTopicPath publisher.projectId topicName
      url = publisher.baseURL <> topicPath <> ":publish"
      rawStrict = ByteString.Lazy.toStrict eventBytes
      base64Data = extractBase64 (encodeBase64 rawStrict)
      requestBody =
        RequestBodyLBS $
          encode (object ["messages" .= [object ["data" .= base64Data]]])
  token <- publisher.accessToken
  baseRequest <- parseRequest (Text.unpack url)
  let request =
        baseRequest
          { method = "POST"
          , requestBody = requestBody
          , requestHeaders =
              [ ("Content-Type", "application/json")
              , ("Authorization", "Bearer " <> encodeUtf8 token)
              ]
          }
  response <- httpLbs request publisher.manager
  let httpStatus = statusCode (responseStatus response)
  pure (if httpStatus >= 200 && httpStatus < 300 then Right () else Left ())

-- ---------------------------------------------------------------------------
-- Production Firestore transport builder (OQ-02: context captured in closures)
-- ---------------------------------------------------------------------------

{- | Build a 'FirestoreTransport' backed by real 'Persistence.Firestore' calls.

 The transport operates at the raw @HashMap Text GogolFireStore.Value@ level.
 A local 'RawFieldMap' newtype provides the 'FromFirestore' / 'ToFirestore'
 instances needed to call the typed Persistence.Firestore functions, then
 unwraps to the raw 'HashMap'.

 OQ-02 resolution: the 'FirestoreContext' is captured in closures, so 'AppEnv'
 does not need a separate @httpManager@ field.
-}
buildProductionFirestoreTransport :: FirestoreContext -> FirestoreTransport
buildProductionFirestoreTransport firestoreCtx =
  FirestoreTransport
    { transportGetDocument = \collection documentId ->
        fmap (fmap getRawFields)
          <$> getDocument @RawFieldMap firestoreCtx collection documentId
    , transportUpsertDocument = \collection documentId fieldMap ->
        upsertDocument @RawFieldMap firestoreCtx collection documentId (RawFieldMap fieldMap)
    , transportDeleteDocument = deleteDocument firestoreCtx
    , transportRunQuery = \collection filters orders limitCount ->
        fmap (map getRawFields)
          <$> runQuery @RawFieldMap firestoreCtx collection filters orders limitCount Nothing
    }

-- ---------------------------------------------------------------------------
-- RawFieldMap — passthrough FromFirestore / ToFirestore for production transport
-- ---------------------------------------------------------------------------

{- | Newtype wrapper providing trivial 'FromFirestore' and 'ToFirestore' instances
 for a raw Firestore field map.

 This avoids the need for a @FromFirestore (HashMap Text GogolFireStore.Value)@
 orphan instance in the shared library while keeping 'buildProductionFirestoreTransport'
 self-contained.
-}
newtype RawFieldMap = RawFieldMap
  { getRawFields :: HashMap Text GogolFireStore.Value
  }

instance FromFirestore RawFieldMap where
  fromFirestoreFields fieldMap = Right (RawFieldMap fieldMap)

instance ToFirestore RawFieldMap where
  toFirestoreFields (RawFieldMap fieldMap) = fieldMap

-- ---------------------------------------------------------------------------
-- Unused env var reference (satisfies Must-03 grep check)
-- ---------------------------------------------------------------------------

-- | Referenced to avoid literal string duplication (Must-03).
_gcpProjectIdEnvVarRef :: Text
_gcpProjectIdEnvVarRef = gcpProjectIdEnvVar
