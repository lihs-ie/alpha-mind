{- | Pub/Sub push endpoint handler for the portfolio-planner service.

 Implements @POST /pubsub/events@.

 Decode chain:
   1. Raw HTTP body → 'PubSubPushEnvelope' (JSON)
   2. @message.data@ base64 → raw bytes
   3. Raw bytes → 'CloudEvent Value' (decodePubSubPush)
   4. 'CloudEvent Value' → 'ProposeOrdersInput'
   5. Call 'proposeOrders'
   6. On success: fetch aggregates, publish orders.proposed
   7. On failure: publish orders.proposal.failed

 HTTP status mapping (RULE-PP-PRS-001):
   * 'PubSubPushProposalSucceeded'  → 200 (success)
   * 'PubSubPushProposalDuplicate'  → 200 (idempotent)
   * 'PubSubPushSchemaInvalid'      → 200 (permanent; re-delivery would repeat the error)
   * 'PubSubPushProposalFailed'     → 500 (transient; Pub/Sub will re-deliver)
   * 'PubSubPushWriteFailed'        → 500 (transient; Pub/Sub will re-deliver)
-}
module Presentation.PubSubHandler (
  -- * Core logic (IO, usable in unit tests)
  processPubSubPush,

  -- * Seam (injectable usecase runner for unit tests)
  processPubSubPushWith,

  -- * Servant handler
  handlePubSubPush,

  -- * Result type
  PubSubPushResult (..),

  -- * HTTP status mapping
  pubSubPushResultToStatus,

  -- * Input builder (exported for tests)
  cloudEventToSignalPayload,
  SignalPayload (..),
) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.Types qualified as Aeson
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as ByteStringLazy
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID qualified as ULID
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Aggregate (
  OrderProposal,
  OrderProposalIdentifier (..),
  Side (..),
 )
import Domain.OrderProposal.Ports (
  OrderProposalRepository (..),
  ProposalDispatchRepository (..),
 )
import Domain.OrderProposal.ProposalDispatch (
  ProposalDispatch,
  ProposalDispatchIdentifier (..),
 )
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
  StrategySnapshot (..),
 )
import Infrastructure.Publisher.PubSubPortfolioEventPublisher (
  publishOrdersProposalFailed,
  publishOrdersProposed,
  runPubSubPortfolioEventPublisherT,
 )
import Infrastructure.Wire.ReasonCodeWire (reasonCodeToWire)
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (decodePubSubPush)
import Observability.Logging (LogContext (..), LogEnv, logErrorWith, logInfoWith)
import Presentation.AppM (AppEnv (..), runAppM)
import Servant (Handler, ServerError (..), err500, throwError)
import UseCase.PortfolioPlanningService (
  ProposeOrdersInput (..),
  ProposeOrdersResult (..),
  proposeOrders,
 )

-- ---------------------------------------------------------------------------
-- Result type
-- ---------------------------------------------------------------------------

data PubSubPushResult
  = PubSubPushProposalSucceeded
  | PubSubPushProposalDuplicate
  | PubSubPushSchemaInvalid Text
  | PubSubPushProposalFailed Text
  | PubSubPushWriteFailed Text
  deriving stock (Eq, Show)

-- | Maps 'PubSubPushResult' to the HTTP status policy (RULE-PP-PRS-001).
pubSubPushResultToStatus :: PubSubPushResult -> Either ServerError PubSubPushResult
pubSubPushResultToStatus PubSubPushProposalSucceeded = Right PubSubPushProposalSucceeded
pubSubPushResultToStatus PubSubPushProposalDuplicate = Right PubSubPushProposalDuplicate
pubSubPushResultToStatus (PubSubPushSchemaInvalid message) = Right (PubSubPushSchemaInvalid message)
pubSubPushResultToStatus (PubSubPushProposalFailed message) =
  Left err500{errBody = "proposal_failed: " <> encodeUtf8Lazy message}
pubSubPushResultToStatus (PubSubPushWriteFailed message) =
  Left err500{errBody = "write_failed: " <> encodeUtf8Lazy message}

-- ---------------------------------------------------------------------------
-- Signal payload extracted from CloudEvent
-- ---------------------------------------------------------------------------

{- | Parsed payload from a signal.generated CloudEvent.
 Exported so tests can exercise the extraction logic independently.
-}
data SignalPayload = SignalPayload
  { signalSnapshot :: SignalSnapshot
  , strategySnapshot :: StrategySnapshot
  , proposalSymbol :: Text
  , proposalSide :: Side
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------------
-- Core logic (IO — testable without Servant)
-- ---------------------------------------------------------------------------

{- | Process a Pub/Sub push body with an injectable usecase runner (seam).

 The usecase runner argument allows tests to substitute a fake implementation
 without any test code entering src/. The production wrapper 'processPubSubPush'
 passes the real 'runAppM'-based runner.

 The runner receives:
   * currentTime
   * ProposeOrdersInput
   and returns IO ProposeOrdersResult.

 After the use case completes with 'ProposeOrdersSucceeded', the handler
 fetches persisted aggregates via the repository port and publishes events.
 The fetch step uses the 'fetchOrders' argument to keep the seam injectable.
-}
processPubSubPushWith ::
  LogEnv ->
  AppEnv ->
  ( UTCTime ->
    ProposeOrdersInput ->
    IO ProposeOrdersResult
  ) ->
  ( ProposalDispatchIdentifier ->
    [OrderProposalIdentifier] ->
    IO (Maybe ProposalDispatch, [OrderProposal])
  ) ->
  ByteString ->
  IO PubSubPushResult
processPubSubPushWith logEnvironment appEnv runUseCase fetchAggregates body =
  case decodePubSubPush @Value body of
    Left pubSubError -> do
      logSchemaInvalidError logEnvironment (Text.pack (show pubSubError)) Nothing Nothing
      pure (PubSubPushSchemaInvalid (Text.pack (show pubSubError)))
    Right cloudEvent -> do
      let traceText = Just (Text.pack (show cloudEvent.trace))
          identifierText = Just (Text.pack (show cloudEvent.identifier))
      logReceived logEnvironment traceText identifierText cloudEvent.eventType
      case cloudEventToSignalPayload cloudEvent of
        Left schemaError -> do
          logSchemaPayloadError logEnvironment schemaError traceText identifierText
          pure (PubSubPushSchemaInvalid schemaError)
        Right signalPayload -> do
          currentTime <- getCurrentTime
          orderProposalUlid <- ULID.getULID
          let eventIdentifierValue = ProposalDispatchIdentifier cloudEvent.identifier
              orderProposalIdentifierValue = OrderProposalIdentifier orderProposalUlid
              traceValue = Trace cloudEvent.trace
              useCaseInput =
                ProposeOrdersInput
                  { eventIdentifier = eventIdentifierValue
                  , orderProposalIdentifier = orderProposalIdentifierValue
                  , signalSnapshot = signalPayload.signalSnapshot
                  , strategySnapshot = signalPayload.strategySnapshot
                  , proposalSymbol = signalPayload.proposalSymbol
                  , proposalSide = signalPayload.proposalSide
                  , trace = traceValue
                  }
          useCaseResult <- runUseCase currentTime useCaseInput
          pushResult <- publishFromResult appEnv fetchAggregates useCaseResult
          logResult logEnvironment traceText identifierText cloudEvent.eventType pushResult
          pure pushResult

{- | Process a Pub/Sub push body, returning a 'PubSubPushResult'.

 This function runs entirely in 'IO' so it can be called directly from
 unit tests without requiring a Servant 'Handler' context.
-}
processPubSubPush ::
  AppEnv ->
  ByteString ->
  IO PubSubPushResult
processPubSubPush appEnv body =
  processPubSubPushWith
    appEnv.logEnv
    appEnv
    ( \currentTime useCaseInput ->
        runAppM appEnv (proposeOrders currentTime useCaseInput)
    )
    (fetchAggregatesFromStore appEnv)
    body

-- ---------------------------------------------------------------------------
-- Aggregate fetcher (production implementation)
-- ---------------------------------------------------------------------------

fetchAggregatesFromStore ::
  AppEnv ->
  ProposalDispatchIdentifier ->
  [OrderProposalIdentifier] ->
  IO (Maybe ProposalDispatch, [OrderProposal])
fetchAggregatesFromStore appEnv dispatchIdentifier orderIdentifiers =
  runAppM appEnv $ do
    maybeDispatch <- findProposalDispatch dispatchIdentifier
    orders <- traverse fetchOrder orderIdentifiers
    pure (maybeDispatch, concat orders)
 where
  fetchOrder identifier = do
    maybeOrder <- findOrderProposal identifier
    pure (maybe [] pure maybeOrder)

-- ---------------------------------------------------------------------------
-- Publisher helpers
-- ---------------------------------------------------------------------------

publishFromResult ::
  AppEnv ->
  ( ProposalDispatchIdentifier ->
    [OrderProposalIdentifier] ->
    IO (Maybe ProposalDispatch, [OrderProposal])
  ) ->
  ProposeOrdersResult ->
  IO PubSubPushResult
publishFromResult _ _ ProposeOrdersDuplicate = pure PubSubPushProposalDuplicate
publishFromResult appEnv fetchAggregates (ProposeOrdersSucceeded{orders = orderIdentifiers, dispatch = dispatchIdentifier, trace = traceValue}) = do
  (maybeDispatch, orderAggregates) <- fetchAggregates dispatchIdentifier orderIdentifiers
  case maybeDispatch of
    Nothing ->
      pure (PubSubPushWriteFailed "dispatch not found after successful proposal")
    Just dispatch -> do
      runPubSubPortfolioEventPublisherT
        appEnv.pubSubEnv
        (publishOrdersProposed dispatch orderAggregates traceValue)
      pure PubSubPushProposalSucceeded
publishFromResult appEnv _ (ProposeOrdersFailed{reasonCode = failureReasonCode, dispatch = dispatchIdentifier, trace = traceValue}) = do
  runPubSubPortfolioEventPublisherT
    appEnv.pubSubEnv
    (publishOrdersProposalFailed dispatchIdentifier failureReasonCode traceValue)
  pure (PubSubPushProposalFailed (reasonCodeToWire failureReasonCode))

-- ---------------------------------------------------------------------------
-- Servant handler (delegates to processPubSubPush)
-- ---------------------------------------------------------------------------

{- | Servant 'Handler' wrapper around 'processPubSubPush'.

 Translates 'PubSubPushResult' to the appropriate HTTP status via
 'pubSubPushResultToStatus'.
-}
handlePubSubPush ::
  AppEnv ->
  ByteString ->
  Handler PubSubPushResult
handlePubSubPush appEnv body = do
  pushResult <- liftIO (processPubSubPush appEnv body)
  case pubSubPushResultToStatus pushResult of
    Left serverError -> throwError serverError
    Right successResult -> pure successResult

-- ---------------------------------------------------------------------------
-- CloudEvent → SignalPayload conversion
-- ---------------------------------------------------------------------------

{- | Extract 'SignalPayload' from a 'CloudEvent Value'.

 Returns 'Left' with an error message if any required field is missing or
 has an unexpected value.
-}
cloudEventToSignalPayload :: CloudEvent Value -> Either Text SignalPayload
cloudEventToSignalPayload cloudEvent = do
  payloadObject <- asObject cloudEvent.payload
  signalVersionValue <- requireTextField "signalVersion" payloadObject
  modelVersionValue <- requireTextField "modelVersion" payloadObject
  featureVersionValue <- requireTextField "featureVersion" payloadObject
  storagePathValue <- requireTextField "storagePath" payloadObject
  degradationFlagText <- requireTextField "degradationFlag" payloadObject
  degradationFlagValue <- parseDegradationFlag degradationFlagText
  requiresComplianceReviewValue <- requireBoolField "requiresComplianceReview" payloadObject
  symbolValue <- requireTextField "proposalSymbol" payloadObject
  sideText <- requireTextField "proposalSide" payloadObject
  sideValue <- parseSide sideText
  maxOrderCountValue <- requireIntField "maxOrderCount" payloadObject
  maxSingleOrderQtyValue <- requireRationalField "maxSingleOrderQty" payloadObject
  rebalanceThresholdValue <- requireRationalField "rebalanceThreshold" payloadObject
  let signalSnap =
        SignalSnapshot
          { signalVersion = signalVersionValue
          , modelVersion = modelVersionValue
          , featureVersion = featureVersionValue
          , storagePath = storagePathValue
          , degradationFlag = degradationFlagValue
          , requiresComplianceReview = requiresComplianceReviewValue
          }
      strategySnap =
        StrategySnapshot
          { maxOrderCount = maxOrderCountValue
          , maxSingleOrderQty = maxSingleOrderQtyValue
          , rebalanceThreshold = rebalanceThresholdValue
          }
  pure
    SignalPayload
      { signalSnapshot = signalSnap
      , strategySnapshot = strategySnap
      , proposalSymbol = symbolValue
      , proposalSide = sideValue
      }

-- ---------------------------------------------------------------------------
-- JSON extraction helpers
-- ---------------------------------------------------------------------------

asObject :: Value -> Either Text Aeson.Object
asObject (Aeson.Object objectValue) = Right objectValue
asObject _ = Left "payload is not an object"

requireTextField :: Text -> Aeson.Object -> Either Text Text
requireTextField key object =
  case Aeson.parseEither (Aeson..: AesonKey.fromText key) object of
    Left message -> Left ("missing or invalid field: " <> key <> " \x2014 " <> Text.pack message)
    Right value -> Right value

requireBoolField :: Text -> Aeson.Object -> Either Text Bool
requireBoolField key object =
  case Aeson.parseEither (Aeson..: AesonKey.fromText key) object of
    Left message -> Left ("missing or invalid field: " <> key <> " \x2014 " <> Text.pack message)
    Right value -> Right value

requireIntField :: Text -> Aeson.Object -> Either Text Int
requireIntField key object =
  case Aeson.parseEither (Aeson..: AesonKey.fromText key) object of
    Left message -> Left ("missing or invalid field: " <> key <> " \x2014 " <> Text.pack message)
    Right value -> Right value

requireRationalField :: Text -> Aeson.Object -> Either Text Rational
requireRationalField key object =
  let result = Aeson.parseEither (Aeson..: AesonKey.fromText key) object :: Either String Double
   in case result of
        Left message -> Left ("missing or invalid field: " <> key <> " \x2014 " <> Text.pack message)
        Right doubleValue -> Right (toRational doubleValue)

parseDegradationFlag :: Text -> Either Text DegradationFlag
parseDegradationFlag "NORMAL" = Right Normal
parseDegradationFlag "WARN" = Right Warn
parseDegradationFlag "BLOCK" = Right Block
parseDegradationFlag other = Left ("unknown degradationFlag: " <> other)

parseSide :: Text -> Either Text Side
parseSide "BUY" = Right Buy
parseSide "SELL" = Right Sell
parseSide other = Left ("unknown proposalSide: " <> other)

-- ---------------------------------------------------------------------------
-- Logging helpers
-- ---------------------------------------------------------------------------

logReceived :: LogEnv -> Maybe Text -> Maybe Text -> Text -> IO ()
logReceived logEnvironment traceValue identifierValue eventTypeValue =
  logInfoWith
    logEnvironment
    LogContext
      { service = "portfolio-planner"
      , trace = traceValue
      , identifier = identifierValue
      , eventType = Just eventTypeValue
      , reasonCode = Nothing
      , result = Nothing
      , payloadSummary = Nothing
      }
    "pubsub_push_received"

logResult :: LogEnv -> Maybe Text -> Maybe Text -> Text -> PubSubPushResult -> IO ()
logResult logEnvironment traceValue identifierValue eventTypeValue pushResult =
  logInfoWith
    logEnvironment
    LogContext
      { service = "portfolio-planner"
      , trace = traceValue
      , identifier = identifierValue
      , eventType = Just eventTypeValue
      , reasonCode = Nothing
      , result = Just (pushResultLabel pushResult)
      , payloadSummary = Nothing
      }
    "pubsub_push_processed"

logSchemaInvalidError :: LogEnv -> Text -> Maybe Text -> Maybe Text -> IO ()
logSchemaInvalidError logEnvironment errorMessage traceValue identifierValue =
  logErrorWith
    logEnvironment
    LogContext
      { service = "portfolio-planner"
      , trace = traceValue
      , identifier = identifierValue
      , eventType = Nothing
      , reasonCode = Nothing
      , result = Just "schema_invalid"
      , payloadSummary = Nothing
      }
    ("pubsub_decode_failed: " <> errorMessage)

logSchemaPayloadError :: LogEnv -> Text -> Maybe Text -> Maybe Text -> IO ()
logSchemaPayloadError logEnvironment errorMessage traceValue identifierValue =
  logErrorWith
    logEnvironment
    LogContext
      { service = "portfolio-planner"
      , trace = traceValue
      , identifier = identifierValue
      , eventType = Nothing
      , reasonCode = Nothing
      , result = Just "schema_invalid"
      , payloadSummary = Nothing
      }
    ("payload_schema_invalid: " <> errorMessage)

pushResultLabel :: PubSubPushResult -> Text
pushResultLabel PubSubPushProposalSucceeded = "proposal_succeeded"
pushResultLabel PubSubPushProposalDuplicate = "proposal_duplicate"
pushResultLabel (PubSubPushSchemaInvalid _) = "schema_invalid"
pushResultLabel (PubSubPushProposalFailed _) = "proposal_failed"
pushResultLabel (PubSubPushWriteFailed _) = "write_failed"

-- ---------------------------------------------------------------------------
-- Internal helper
-- ---------------------------------------------------------------------------

encodeUtf8Lazy :: Text -> ByteString
encodeUtf8Lazy = ByteStringLazy.fromStrict . TextEncoding.encodeUtf8
