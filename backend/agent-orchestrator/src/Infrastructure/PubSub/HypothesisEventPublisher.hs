{-# LANGUAGE OverloadedRecordDot #-}

{- | Pub/Sub publisher for hypothesis domain events.

Must-17: HypothesisEventPublisher newtype + runHypothesisEventPublisher.
Must-18: HypothesisPublisherEnv with topicName and pubsubPublish (injectable).
Must-19: PUBSUB_TOPIC_HYPOTHESIS environment variable name documented here.
Must-20: publishHypothesisProposed — eventType "hypothesis.proposed".
Must-21: publishHypothesisProposalFailed — eventType "hypothesis.proposal.failed".
Must-22: event identifier is a newly adopted ULID on every publish.
Must-23: guard — only Proposed proposals may use publishHypothesisProposed.
Must-24: guard — only Failed/Blocked proposals may use publishHypothesisProposalFailed.

Environment variable: @PUBSUB_TOPIC_HYPOTHESIS@ — Pub/Sub topic for hypothesis events.
-}
module Infrastructure.PubSub.HypothesisEventPublisher (
  -- * Environment variable name (Must-19)
  hypothesisPubSubTopicEnvVar,

  -- * Environment
  HypothesisPublisherEnv (..),

  -- * Monad transformer (Must-17)
  HypothesisEventPublisher (..),
  runHypothesisEventPublisher,

  -- * Publisher functions (Must-20/21)
  publishHypothesisProposed,
  publishHypothesisProposalFailed,
) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson (ToJSON (..), encode, object, (.=))
import Data.ByteString.Lazy (ByteString)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Data.ULID qualified as ULID
import Domain.HypothesisOrchestration (Trace (..))
import Domain.HypothesisOrchestration.Aggregate (
  HypothesisProposal,
  HypothesisProposalIdentifier (..),
  InstrumentType (..),
  ProposalStatus (..),
 )
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.ValueObjects (InsiderRiskLevel (..))

-- ---------------------------------------------------------------------------
-- Environment variable name (Must-19)
-- ---------------------------------------------------------------------------

{- | Must-19: Environment variable for hypothesis Pub/Sub topic name.
Value is read at startup by 'Main.hs' wiring; not read by this module itself.
-}
hypothesisPubSubTopicEnvVar :: Text
hypothesisPubSubTopicEnvVar = "PUBSUB_TOPIC_HYPOTHESIS"

-- ---------------------------------------------------------------------------
-- Environment (Must-18)
-- ---------------------------------------------------------------------------

{- | Must-18: Publisher environment.

Fields:
  * 'topicName' — Pub/Sub topic name (read from @PUBSUB_TOPIC_HYPOTHESIS@).
  * 'pubsubPublish' — injectable transport: @(topicName, messageBytes) → IO ()@.
    Replaced with an 'IORef'-capturing function in tests (Must-28).
-}
data HypothesisPublisherEnv = HypothesisPublisherEnv
  { topicName :: Text
  -- ^ Must-18: Pub/Sub topic name from @PUBSUB_TOPIC_HYPOTHESIS@.
  , pubsubPublish :: Text -> ByteString -> IO ()
  -- ^ Must-18: Injectable transport — no real Pub/Sub calls when replaced in tests.
  }

-- ---------------------------------------------------------------------------
-- Monad transformer (Must-17)
-- ---------------------------------------------------------------------------

-- | Must-17: Monad transformer wrapping 'ReaderT HypothesisPublisherEnv'.
newtype HypothesisEventPublisher m a = HypothesisEventPublisher
  { unHypothesisEventPublisher :: ReaderT HypothesisPublisherEnv m a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO)

-- | Must-17: Run a 'HypothesisEventPublisher' action with the given environment.
runHypothesisEventPublisher :: HypothesisPublisherEnv -> HypothesisEventPublisher m a -> m a
runHypothesisEventPublisher environment action =
  runReaderT (unHypothesisEventPublisher action) environment

-- ---------------------------------------------------------------------------
-- Payload types
-- ---------------------------------------------------------------------------

data HypothesisProposedPayload = HypothesisProposedPayload
  { hypothesis :: Text
  , symbol :: Text
  , instrumentType :: Text
  , title :: Text
  , sourceEvidence :: [Text]
  , insiderRisk :: Maybe Text
  , mnpiSelfDeclared :: Maybe Bool
  , reportPath :: Maybe Text
  }
  deriving stock (Eq, Show)

instance ToJSON HypothesisProposedPayload where
  toJSON payloadValue =
    object $
      [ "hypothesis" .= payloadValue.hypothesis
      , "symbol" .= payloadValue.symbol
      , "instrumentType" .= payloadValue.instrumentType
      , "title" .= payloadValue.title
      , "sourceEvidence" .= payloadValue.sourceEvidence
      ]
        <> maybe [] (\risk -> ["insiderRisk" .= risk]) payloadValue.insiderRisk
        <> maybe [] (\declared -> ["mnpiSelfDeclared" .= declared]) payloadValue.mnpiSelfDeclared
        <> maybe [] (\path -> ["reportPath" .= path]) payloadValue.reportPath

data HypothesisProposalFailedPayload = HypothesisProposalFailedPayload
  { hypothesis :: Text
  , reasonCode :: Text
  , dispatch :: Text
  }
  deriving stock (Eq, Show)

instance ToJSON HypothesisProposalFailedPayload where
  toJSON payloadValue =
    object
      [ "hypothesis" .= payloadValue.hypothesis
      , "reasonCode" .= payloadValue.reasonCode
      , "dispatch" .= payloadValue.dispatch
      ]

-- ---------------------------------------------------------------------------
-- Event envelope types
-- ---------------------------------------------------------------------------

data HypothesisProposedEvent = HypothesisProposedEvent
  { identifier :: ULID
  , eventType :: Text
  , occurredAt :: UTCTime
  , trace :: ULID
  , schemaVersion :: Text
  , skillVersion :: Text
  , instructionProfileVersion :: Text
  , payload :: HypothesisProposedPayload
  }

instance ToJSON HypothesisProposedEvent where
  toJSON e =
    object
      [ "identifier" .= Text.pack (show e.identifier)
      , "eventType" .= e.eventType
      , "occurredAt" .= e.occurredAt
      , "trace" .= Text.pack (show e.trace)
      , "schemaVersion" .= e.schemaVersion
      , "skillVersion" .= e.skillVersion
      , "instructionProfileVersion" .= e.instructionProfileVersion
      , "payload" .= e.payload
      ]

data HypothesisFailedEvent = HypothesisFailedEvent
  { identifier :: ULID
  , eventType :: Text
  , occurredAt :: UTCTime
  , trace :: ULID
  , schemaVersion :: Text
  , payload :: HypothesisProposalFailedPayload
  }

instance ToJSON HypothesisFailedEvent where
  toJSON e =
    object
      [ "identifier" .= Text.pack (show e.identifier)
      , "eventType" .= e.eventType
      , "occurredAt" .= e.occurredAt
      , "trace" .= Text.pack (show e.trace)
      , "schemaVersion" .= e.schemaVersion
      , "payload" .= e.payload
      ]

-- ---------------------------------------------------------------------------
-- Internal codec helpers
-- ---------------------------------------------------------------------------

instrumentTypeToText :: InstrumentType -> Text
instrumentTypeToText ETF = "ETF"
instrumentTypeToText Stock = "STOCK"

insiderRiskToText :: InsiderRiskLevel -> Text
insiderRiskToText Low = "low"
insiderRiskToText Medium = "medium"
insiderRiskToText High = "high"

reasonCodeToText :: ReasonCode -> Text
reasonCodeToText ResourceNotFound = "RESOURCE_NOT_FOUND"
reasonCodeToText RequestValidationFailed = "REQUEST_VALIDATION_FAILED"
reasonCodeToText StateConflict = "STATE_CONFLICT"
reasonCodeToText IdempotencyDuplicateEvent = "IDEMPOTENCY_DUPLICATE_EVENT"
reasonCodeToText DependencyTimeout = "DEPENDENCY_TIMEOUT"
reasonCodeToText DependencyUnavailable = "DEPENDENCY_UNAVAILABLE"

proposalStatusLabel :: ProposalStatus -> Text
proposalStatusLabel Pending = "pending"
proposalStatusLabel Proposed = "proposed"
proposalStatusLabel Blocked = "blocked"
proposalStatusLabel Failed = "failed"

-- ---------------------------------------------------------------------------
-- Publisher functions
-- ---------------------------------------------------------------------------

{- | Must-20: Publish a @hypothesis.proposed@ event to Pub/Sub.
Must-23: Only 'Proposed' proposals are accepted; other statuses return
'Left (InvalidStateTransition ...)' without publishing.
Must-22: A new ULID is generated for the event 'identifier' on every call.
-}
publishHypothesisProposed ::
  HypothesisProposal ->
  HypothesisEventPublisher IO (Either DomainError ())
publishHypothesisProposed proposal = HypothesisEventPublisher $ do
  environment <- ask
  case proposal.status of
    Proposed -> liftIO $ do
      now <- getCurrentTime
      eventIdentifier <- ULID.getULID
      let proposalId = proposal.identifier
          proposalTrace = proposal.trace
          HypothesisProposalIdentifier proposalUlid = proposalId
          Trace traceUlid = proposalTrace
          payloadValue =
            HypothesisProposedPayload
              { hypothesis = Text.pack (show proposalUlid)
              , symbol = fromMaybe "" proposal.symbol
              , instrumentType = maybe "STOCK" instrumentTypeToText proposal.instrumentType
              , title = fromMaybe "" proposal.title
              , sourceEvidence = proposal.sourceEvidence
              , insiderRisk = fmap insiderRiskToText proposal.insiderRisk
              , mnpiSelfDeclared = proposal.mnpiSelfDeclared
              , reportPath = proposal.reportPath
              }
          event =
            HypothesisProposedEvent
              { identifier = eventIdentifier
              , eventType = "hypothesis.proposed"
              , occurredAt = now
              , trace = traceUlid
              , schemaVersion = "1.0.0"
              , skillVersion = fromMaybe "" proposal.skillVersion
              , instructionProfileVersion = fromMaybe "" proposal.instructionProfileVersion
              , payload = payloadValue
              }
      environment.pubsubPublish environment.topicName (encode event)
      pure (Right ())
    other ->
      pure (Left (InvalidStateTransition (proposalStatusLabel other) "PublishHypothesisProposed" StateConflict))

{- | Must-21: Publish a @hypothesis.proposal.failed@ event to Pub/Sub.
Must-24: Only 'Failed' or 'Blocked' proposals are accepted; other statuses return
'Left (InvalidStateTransition ...)' without publishing.
Must-22: A new ULID is generated for the event 'identifier' on every call.
-}
publishHypothesisProposalFailed ::
  HypothesisProposal ->
  ReasonCode ->
  HypothesisEventPublisher IO (Either DomainError ())
publishHypothesisProposalFailed proposal reasonCode = HypothesisEventPublisher $ do
  environment <- ask
  case proposal.status of
    Failed -> liftIO (doPublishFailed environment proposal reasonCode)
    Blocked -> liftIO (doPublishFailed environment proposal reasonCode)
    other ->
      pure (Left (InvalidStateTransition (proposalStatusLabel other) "PublishHypothesisProposalFailed" StateConflict))

doPublishFailed ::
  HypothesisPublisherEnv ->
  HypothesisProposal ->
  ReasonCode ->
  IO (Either DomainError ())
doPublishFailed environment proposal reasonCode = do
  now <- getCurrentTime
  eventIdentifier <- ULID.getULID
  let proposalId = proposal.identifier
      proposalTrace = proposal.trace
      HypothesisProposalIdentifier proposalUlid = proposalId
      Trace traceUlid = proposalTrace
      payloadValue =
        HypothesisProposalFailedPayload
          { hypothesis = Text.pack (show proposalUlid)
          , reasonCode = reasonCodeToText reasonCode
          , dispatch = proposal.dispatch
          }
      event =
        HypothesisFailedEvent
          { identifier = eventIdentifier
          , eventType = "hypothesis.proposal.failed"
          , occurredAt = now
          , trace = traceUlid
          , schemaVersion = "1.0.0"
          , payload = payloadValue
          }
  environment.pubsubPublish environment.topicName (encode event)
  pure (Right ())
