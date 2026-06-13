{-# LANGUAGE GeneralizedNewtypeDeriving #-}

{- | Application monad for the audit-log service.

 'AppM' is a flat @ReaderT AppEnv IO@ that provides all four repository /
 publisher instances required by 'recordAuditFromSourceEvent':

   * 'AuditRecordRepository'
   * 'AuditIngestionRepository'
   * 'AuditArchiveRepository'
   * 'AuditEventPublisher'

 Each instance delegates to the corresponding Firestore transformer by
 extracting the relevant sub-environment from 'AppEnv' and calling its
 @run*T@ function.  This keeps the existing transformer implementations
 unchanged (Non-goal: no domain / infra changes).
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

import Config.Env (CommonRuntimeEnv (..), loadCommonRuntimeEnv, requireTextEnv)
import Control.Monad.IO.Class (MonadIO (liftIO))
import Control.Monad.Trans.Reader (ReaderT (..), ask, runReaderT)
import Data.Aeson (Value, object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.ULID (ULID)
import Domain.AuditLog (Trace (..))
import Domain.AuditLog.AuditIngestion (AuditIngestionRepository (..))
import Domain.AuditLog.AuditIngestion qualified as AuditIngestion
import Domain.AuditLog.AuditRecord (AuditArchiveRepository (..), AuditRecord, AuditRecordRepository (..))
import Domain.AuditLog.AuditRecord qualified as AuditRecord
import Infrastructure.Repository.FirestoreAuditIngestionRepository (
  FirestoreAuditIngestionEnv (..),
  runFirestoreAuditIngestionT,
 )
import Infrastructure.Repository.FirestoreAuditRecordRepository (
  FirestoreAuditArchiveEnv (..),
  FirestoreAuditRecordEnv (..),
  runFirestoreAuditArchiveT,
  runFirestoreAuditRecordT,
 )
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubPublisher (..), TopicName, publishCloudEvent)
import Network.HTTP.Client.TLS (newTlsManager)
import Observability.Logging (LogEnv, initLogger)
import Persistence.Firestore (FirestoreContext (..))
import UseCase.RecordAuditFromSourceEvent (AuditEventPublisher (..))

-- ---------------------------------------------------------------------------
-- Application environment
-- ---------------------------------------------------------------------------

data AppEnv = AppEnv
  { firestoreContext :: FirestoreContext
  , logEnv :: LogEnv
  , pubSubPublisher :: PubSubPublisher
  , auditTopicName :: TopicName
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
-- AuditRecordRepository instance
-- Delegates to FirestoreAuditRecordT via runFirestoreAuditRecordT.
-- ---------------------------------------------------------------------------

instance AuditRecordRepository AppM where
  find recordIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreAuditRecordEnv{firestoreContext = appEnv.firestoreContext}
        action = AuditRecord.find recordIdentifier
    liftIO $ runFirestoreAuditRecordT firestoreEnv action

  findByEventType eventTypeValue = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreAuditRecordEnv{firestoreContext = appEnv.firestoreContext}
        action = AuditRecord.findByEventType eventTypeValue
    liftIO $ runFirestoreAuditRecordT firestoreEnv action

  findByTrace traceValue = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreAuditRecordEnv{firestoreContext = appEnv.firestoreContext}
        action = AuditRecord.findByTrace traceValue
    liftIO $ runFirestoreAuditRecordT firestoreEnv action

  search criteria = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreAuditRecordEnv{firestoreContext = appEnv.firestoreContext}
        action = AuditRecord.search criteria
    liftIO $ runFirestoreAuditRecordT firestoreEnv action

  persist record = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreAuditRecordEnv{firestoreContext = appEnv.firestoreContext}
        action = AuditRecord.persist record
    liftIO $ runFirestoreAuditRecordT firestoreEnv action

  terminate recordIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreAuditRecordEnv{firestoreContext = appEnv.firestoreContext}
        action = AuditRecord.terminate recordIdentifier
    liftIO $ runFirestoreAuditRecordT firestoreEnv action

-- ---------------------------------------------------------------------------
-- AuditIngestionRepository instance
-- Delegates to FirestoreAuditIngestionT via runFirestoreAuditIngestionT.
-- ---------------------------------------------------------------------------

instance AuditIngestionRepository AppM where
  find ingestionIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreAuditIngestionEnv{firestoreContext = appEnv.firestoreContext}
        action = AuditIngestion.find ingestionIdentifier
    liftIO $ runFirestoreAuditIngestionT firestoreEnv action

  persist ingestion = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreAuditIngestionEnv{firestoreContext = appEnv.firestoreContext}
        action = AuditIngestion.persist ingestion
    liftIO $ runFirestoreAuditIngestionT firestoreEnv action

  terminate ingestionIdentifier = AppM $ do
    appEnv <- ask
    let firestoreEnv = FirestoreAuditIngestionEnv{firestoreContext = appEnv.firestoreContext}
        action = AuditIngestion.terminate ingestionIdentifier
    liftIO $ runFirestoreAuditIngestionT firestoreEnv action

-- ---------------------------------------------------------------------------
-- AuditArchiveRepository instance
-- Delegates to FirestoreAuditArchiveT via runFirestoreAuditArchiveT.
-- ---------------------------------------------------------------------------

instance AuditArchiveRepository AppM where
  persistArchive archive = AppM $ do
    appEnv <- ask
    let archiveEnv = FirestoreAuditArchiveEnv{logEnv = appEnv.logEnv}
        action = AuditRecord.persistArchive archive
    liftIO $ runFirestoreAuditArchiveT archiveEnv action

-- ---------------------------------------------------------------------------
-- AuditEventPublisher instance
-- Publishes to the audit.recorded topic using PubSub best-effort publish.
-- Failure is logged but does not propagate (best-effort — internal design §5).
-- ---------------------------------------------------------------------------

instance AuditEventPublisher AppM where
  publishAuditRecorded record = AppM $ do
    appEnv <- ask
    let recordIdentifier = record.identifier
        recordTrace = record.trace
        event =
          CloudEvent
            { identifier = recordIdentifier.value
            , eventType = "audit.recorded"
            , occurredAt = record.occurredAt
            , trace = extractTraceValue recordTrace
            , schemaVersion = "1.0"
            , payload = buildAuditRecordedPayload record
            }
    _ <- liftIO $ publishCloudEvent appEnv.pubSubPublisher appEnv.auditTopicName event
    pure ()

extractTraceValue :: Trace -> ULID
extractTraceValue (Trace ulidValue) = ulidValue

buildAuditRecordedPayload :: AuditRecord -> Value
buildAuditRecordedPayload record =
  object
    [ "identifier" .= Text.pack (show record.identifier.value)
    , "eventType" .= record.eventType
    , "service" .= record.service
    ]

-- ---------------------------------------------------------------------------
-- Environment construction
-- ---------------------------------------------------------------------------

buildAppEnv :: IO AppEnv
buildAppEnv = do
  runtimeEnv <- loadCommonRuntimeEnv "audit-log"
  logEnvironment <- initLogger runtimeEnv
  topicName <- requireTextEnv "PUBSUB_AUDIT_TOPIC"
  projectIdentifier <- pure runtimeEnv.gcpProjectId
  httpManager <- newTlsManager
  let firestoreCtx =
        FirestoreContext
          { projectId = projectIdentifier
          , databaseId = "(default)"
          }
      publisher =
        PubSubPublisher
          { manager = httpManager
          , projectId = projectIdentifier
          , baseURL = "https://pubsub.googleapis.com/v1/"
          , accessToken = pure ""
          }
  pure
    AppEnv
      { firestoreContext = firestoreCtx
      , logEnv = logEnvironment
      , pubSubPublisher = publisher
      , auditTopicName = topicName
      , serviceName = "audit-log"
      }
