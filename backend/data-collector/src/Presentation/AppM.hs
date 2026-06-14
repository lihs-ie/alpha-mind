{-# LANGUAGE GeneralizedNewtypeDeriving #-}

{- | Application monad for the data-collector service.

 'AppM' is a flat @ReaderT AppEnv IO@ that provides all six port instances
 required by 'collectMarketData':

   * 'MarketCollectionRepository'   → FirestoreMarketCollectionRepositoryT
   * 'CollectionDispatchRepository' → FirestoreCollectionDispatchRepositoryT
   * 'MarketDataSource'             → JQuantsMarketDataSourceT (JP) / AlpacaMarketDataSourceT (US)
   * 'RawMarketDataPort'            → GcsMarketDataRepositoryT
   * 'CollectionEventPublisher'     → PubSubCollectionEventPublisherT
   * 'CollectionAuditPort'          → CloudLoggingCollectionAuditWriterT

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
import Data.Text (Text)
import Domain.MarketCollection.Aggregate (
  MarketCollectionIdentifier,
  MarketCollectionRepository (..),
 )
import Domain.MarketCollection.Aggregate qualified as MarketCollectionRepo
import Domain.MarketCollection.CollectionDispatch (
  CollectionDispatchRepository (..),
 )
import Domain.MarketCollection.CollectionDispatch qualified as CollectionDispatchRepo
import Domain.MarketCollection.CollectionQualityPolicy (MarketSchemaIntegritySpecification (..))
import Domain.MarketCollection.MarketDataSource (MarketDataSource (..))
import Domain.MarketCollection.SourcePolicySpecificationService (ApprovedSourceSpecification (..))
import Infrastructure.ACL.AlpacaMarketDataSourceT (
  AlpacaEnv (..),
  runAlpacaMarketDataSourceT,
 )
import Infrastructure.ACL.JQuantsMarketDataSourceT (
  JQuantsEnv (..),
  runJQuantsMarketDataSourceT,
 )
import Infrastructure.ACL.NisshokinCsvSourceAdapter (NisshokinEnv (..))
import Infrastructure.Logging.CloudLoggingCollectionAuditWriter (
  CloudLoggingCollectionAuditWriterEnv (..),
  runCloudLoggingCollectionAuditWriterT,
 )
import Infrastructure.Publisher.PubSubCollectionEventPublisher (
  PubSubCollectionEventPublisherEnv (..),
  runPubSubCollectionEventPublisherT,
 )
import Infrastructure.Repository.FirestoreCollectionDispatchRepository (
  FirestoreCollectionDispatchEnv (..),
  runFirestoreCollectionDispatchRepositoryT,
 )
import Infrastructure.Repository.FirestoreMarketCollectionRepository (
  FirestoreMarketCollectionEnv (..),
  runFirestoreMarketCollectionRepositoryT,
 )
import Infrastructure.Repository.GcsMarketDataRepository (
  GcsMarketDataEnv (..),
  mkProductionUploadFn,
  runGcsMarketDataRepositoryT,
 )
import Messaging.PubSub (PubSubPublisher (..))
import Network.HTTP.Client (httpLbs)
import Network.HTTP.Client.TLS (newTlsManager)
import Observability.Logging (LogContext (..), LogEnv, initLogger, logInfoWith)
import Persistence.Firestore (FirestoreContext (..))
import Storage.GCS (defaultGcsContext)
import UseCase.CollectMarketData (
  CollectionEventPublisher (..),
  RawMarketDataPort (..),
 )
import UseCase.RecordCollectionAudit (
  CollectionAuditPort (..),
 )
import UseCase.RecordCollectionAudit qualified as AuditPort

-- ---------------------------------------------------------------------------
-- Application environment
-- ---------------------------------------------------------------------------

{- | Must-07: AppEnv holds all sub-environments plus static specifications
 (design decision 4: ApprovedSourceSpecification / MarketSchemaIntegritySpecification
 are constructed once in buildAppEnv and held in AppEnv).
-}
data AppEnv = AppEnv
  { firestoreContext :: FirestoreContext
  , logEnv :: LogEnv
  , gcsEnv :: GcsMarketDataEnv
  , jQuantsEnv :: JQuantsEnv
  , alpacaEnv :: AlpacaEnv
  , pubSubEnv :: PubSubCollectionEventPublisherEnv
  , auditLogEnv :: CloudLoggingCollectionAuditWriterEnv
  , serviceName :: Text
  , approvedSourceSpecification :: ApprovedSourceSpecification
  , schemaIntegritySpecification :: MarketSchemaIntegritySpecification
  }

-- ---------------------------------------------------------------------------
-- Application monad
-- ---------------------------------------------------------------------------

newtype AppM a = AppM {unAppM :: ReaderT AppEnv IO a}
  deriving newtype (Functor, Applicative, Monad, MonadIO)

runAppM :: AppEnv -> AppM a -> IO a
runAppM appEnv action = runReaderT (unAppM action) appEnv

-- ---------------------------------------------------------------------------
-- MarketCollectionRepository instance
-- Delegates to FirestoreMarketCollectionRepositoryT.
-- ---------------------------------------------------------------------------

instance MarketCollectionRepository AppM where
  find collectionIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreMarketCollectionEnv{firestoreContext = appEnv.firestoreContext}
        action = MarketCollectionRepo.find collectionIdentifier
    liftIO $ runFirestoreMarketCollectionRepositoryT firestoreEnv action

  findByStatus statusValue = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreMarketCollectionEnv{firestoreContext = appEnv.firestoreContext}
        action = MarketCollectionRepo.findByStatus statusValue
    liftIO $ runFirestoreMarketCollectionRepositoryT firestoreEnv action

  search criteria = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreMarketCollectionEnv{firestoreContext = appEnv.firestoreContext}
        action = MarketCollectionRepo.search criteria
    liftIO $ runFirestoreMarketCollectionRepositoryT firestoreEnv action

  persist collection = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreMarketCollectionEnv{firestoreContext = appEnv.firestoreContext}
        action = MarketCollectionRepo.persist collection
    liftIO $ runFirestoreMarketCollectionRepositoryT firestoreEnv action

  terminate collectionIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreMarketCollectionEnv{firestoreContext = appEnv.firestoreContext}
        action = MarketCollectionRepo.terminate collectionIdentifier
    liftIO $ runFirestoreMarketCollectionRepositoryT firestoreEnv action

-- ---------------------------------------------------------------------------
-- CollectionDispatchRepository instance
-- Delegates to FirestoreCollectionDispatchRepositoryT.
-- ---------------------------------------------------------------------------

instance CollectionDispatchRepository AppM where
  find collectionIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreCollectionDispatchEnv{firestoreContext = appEnv.firestoreContext}
        action = CollectionDispatchRepo.find collectionIdentifier
    liftIO $ runFirestoreCollectionDispatchRepositoryT firestoreEnv action

  persist dispatch = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreCollectionDispatchEnv{firestoreContext = appEnv.firestoreContext}
        action = CollectionDispatchRepo.persist dispatch
    liftIO $ runFirestoreCollectionDispatchRepositoryT firestoreEnv action

  terminate collectionIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreCollectionDispatchEnv{firestoreContext = appEnv.firestoreContext}
        action = CollectionDispatchRepo.terminate collectionIdentifier
    liftIO $ runFirestoreCollectionDispatchRepositoryT firestoreEnv action

-- ---------------------------------------------------------------------------
-- MarketDataSource instance
-- Must-11: fetchJapanMarketData → JQuantsMarketDataSourceT
-- Must-12: fetchUsMarketData    → AlpacaMarketDataSourceT (usCollectionEnabled=False in MVP)
-- Design decision 3: dispatch per method, not per combined transformer.
-- ---------------------------------------------------------------------------

instance MarketDataSource AppM where
  fetchJapanMarketData targetDay = AppM $ do
    appEnv <- ask
    let jqEnv = appEnv.jQuantsEnv
    liftIO $ runJQuantsMarketDataSourceT jqEnv (fetchJapanMarketData targetDay)

  fetchUsMarketData targetDay = AppM $ do
    appEnv <- ask
    let alpEnv = appEnv.alpacaEnv
    liftIO $ runAlpacaMarketDataSourceT alpEnv (fetchUsMarketData targetDay)

-- ---------------------------------------------------------------------------
-- RawMarketDataPort instance
-- Delegates to GcsMarketDataRepositoryT.
-- ---------------------------------------------------------------------------

instance RawMarketDataPort AppM where
  persistRawMarketData collectionIdentifier targetDay dataset = AppM $ do
    appEnv <- ask
    let gcsEnvironment = appEnv.gcsEnv
        action = persistRawMarketData collectionIdentifier targetDay dataset
    liftIO $ runGcsMarketDataRepositoryT gcsEnvironment action

-- ---------------------------------------------------------------------------
-- CollectionEventPublisher instance
-- Delegates to PubSubCollectionEventPublisherT.
-- ---------------------------------------------------------------------------

instance CollectionEventPublisher AppM where
  publishMarketCollected collectionIdentifier artifact traceValue = AppM $ do
    appEnv <- ask
    let pubSubEnvironment = appEnv.pubSubEnv
        action = publishMarketCollected collectionIdentifier artifact traceValue
    liftIO $ runPubSubCollectionEventPublisherT pubSubEnvironment action

  publishMarketCollectFailed collectionIdentifier reasonCode maybeDetail traceValue = AppM $ do
    appEnv <- ask
    let pubSubEnvironment = appEnv.pubSubEnv
        action = publishMarketCollectFailed collectionIdentifier reasonCode maybeDetail traceValue
    liftIO $ runPubSubCollectionEventPublisherT pubSubEnvironment action

-- ---------------------------------------------------------------------------
-- CollectionAuditPort instance
-- Delegates to CloudLoggingCollectionAuditWriterT.
-- ---------------------------------------------------------------------------

instance CollectionAuditPort AppM where
  writeCollectionAudit collectionIdentifier traceValue entry = AppM $ do
    appEnv <- ask
    let auditEnvironment = appEnv.auditLogEnv
        action = AuditPort.writeCollectionAudit collectionIdentifier traceValue entry
    liftIO $ runCloudLoggingCollectionAuditWriterT auditEnvironment action

-- ---------------------------------------------------------------------------
-- Environment construction
-- ---------------------------------------------------------------------------

{- | Must-08: Build 'AppEnv' from environment variables.
 Required variables:
   GCP_PROJECT_ID (or GOOGLE_CLOUD_PROJECT) — via loadCommonRuntimeEnv
   SERVICE_VERSION                           — via loadCommonRuntimeEnv
   PORT                                      — via loadCommonRuntimeEnv (default 8080)
   GCS_BUCKET_NAME
   PUBSUB_MARKET_COLLECTED_TOPIC
   PUBSUB_MARKET_COLLECT_FAILED_TOPIC
   JQUANTS_ID_TOKEN
   ALPACA_API_KEY_ID
   ALPACA_API_SECRET_KEY
 Optional:
   ALPACA_US_COLLECTION_ENABLED (default false)
   FIRESTORE_DATABASE_ID        (default "(default)")
-}
buildAppEnv :: IO AppEnv
buildAppEnv = do
  runtimeEnv <- loadCommonRuntimeEnv "data-collector"
  logEnvironment <- initLogger runtimeEnv
  let projectIdentifier = runtimeEnv.gcpProjectId

  -- GCS
  bucketNameValue <- requireTextEnv "GCS_BUCKET_NAME"
  let gcsContextValue = defaultGcsContext
      productionUploadFn = mkProductionUploadFn gcsContextValue
      gcsEnvironment =
        GcsMarketDataEnv
          { gcsContext = gcsContextValue
          , bucketName = bucketNameValue
          , uploadFn = productionUploadFn
          }

  -- Pub/Sub
  collectedTopicNameValue <- requireTextEnv "PUBSUB_MARKET_COLLECTED_TOPIC"
  failedTopicNameValue <- requireTextEnv "PUBSUB_MARKET_COLLECT_FAILED_TOPIC"
  httpManager <- newTlsManager
  let pubSubPublisher =
        PubSubPublisher
          { manager = httpManager
          , projectId = projectIdentifier
          , baseURL = "https://pubsub.googleapis.com/v1/"
          , accessToken = pure ""
          }
      pubSubEnvironment =
        PubSubCollectionEventPublisherEnv
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

  -- J-Quants — httpExecute uses a shared TLS manager via closure
  jQuantsIdToken <- requireTextEnv "JQUANTS_ID_TOKEN"
  httpManagerForAcl <- newTlsManager
  let onBrowserFallback = logInfoWith logEnvironment nisshokinLogContext
      nisshokinLogContext =
        LogContext
          { service = "data-collector"
          , trace = Nothing
          , identifier = Nothing
          , eventType = Just "browser_fallback"
          , reasonCode = Nothing
          , result = Nothing
          , payloadSummary = Nothing
          }
      executeHttpWithManager = (`httpLbs` httpManagerForAcl)
      nisshokinEnvironment =
        NisshokinEnv
          { timeoutSeconds = 60
          , httpExecute = executeHttpWithManager
          , browserFallback = \_targetDay -> pure (Right [])
          , onBrowserFallback = onBrowserFallback
          }
      jQuantsEnvironment =
        JQuantsEnv
          { baseUrl = "https://api.jquants-pro.com/v2"
          , idToken = jQuantsIdToken
          , timeoutSeconds = 30
          , httpExecute = executeHttpWithManager
          , nisshokinEnv = nisshokinEnvironment
          }

  -- Alpaca
  alpacaApiKeyIdentifier <- requireTextEnv "ALPACA_API_KEY_ID"
  alpacaApiSecretKeyValue <- requireTextEnv "ALPACA_API_SECRET_KEY"
  maybeUsCollectionEnabled <- optionalTextEnv "ALPACA_US_COLLECTION_ENABLED"
  let usCollectionEnabledValue = case maybeUsCollectionEnabled of
        Just "true" -> True
        _ -> False
      alpacaEnvironment =
        AlpacaEnv
          { usCollectionEnabled = usCollectionEnabledValue
          , apiKeyIdentifier = alpacaApiKeyIdentifier
          , apiSecretKey = alpacaApiSecretKeyValue
          , timeoutSeconds = 30
          , baseUrl = "https://data.alpaca.markets/v2"
          , httpExecute = executeHttpWithManager
          }

  -- Audit log
  let auditLogEnvironment =
        CloudLoggingCollectionAuditWriterEnv
          { logEnv = logEnvironment
          }

  pure
    AppEnv
      { firestoreContext = firestoreCtx
      , logEnv = logEnvironment
      , gcsEnv = gcsEnvironment
      , jQuantsEnv = jQuantsEnvironment
      , alpacaEnv = alpacaEnvironment
      , pubSubEnv = pubSubEnvironment
      , auditLogEnv = auditLogEnvironment
      , serviceName = "data-collector"
      , approvedSourceSpecification =
          ApprovedSourceSpecification
            { approvedSources = []
            }
      , schemaIntegritySpecification =
          MarketSchemaIntegritySpecification
            { requiredFields = []
            }
      }
