module Presentation.Handler.Commands (
  CommandAccepted (..),
  RunCycleRequest (..),
  RunInsightCycleRequest (..),
  RunInsightCycleOptions (..),
  handleRunCycle,
  handleRunInsightCycle,
) where

import Control.Exception (SomeException, try)
import Control.Monad (unless, when)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (
  FromJSON (..),
  ToJSON (..),
  encode,
  object,
  withObject,
  (.:?),
  (.=),
 )
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (getCurrentTime, utctDay)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.ULID qualified as ULID
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Publisher.PubSubCommandsPublisher (
  InsightCollectOptions (..),
  PubSubCommandsPublisherEnv (..),
  publishInsightCollectRequested,
  publishMarketCollectRequested,
 )
import Infrastructure.Repository.FirestoreOperationsRepository (
  FirestoreOperationsRepositoryEnv (..),
  OperationsRuntime,
  getOperationsRuntime,
  operationsKillSwitchEnabled,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err401, err403, err409, err503, throwError)

-- ---------------------------------------------------------------------------
-- Request types
-- ---------------------------------------------------------------------------

-- | Optional body for @POST \/commands\/run-cycle@.
newtype RunCycleRequest = RunCycleRequest
  { mode :: Maybe Text
  -- ^ Always @\"manual\"@ when supplied.
  }

instance FromJSON RunCycleRequest where
  parseJSON =
    withObject "RunCycleRequest" $ \requestObject ->
      RunCycleRequest
        <$> requestObject .:? "mode"

-- | Options nested in 'RunInsightCycleRequest'.
data RunInsightCycleOptions = RunInsightCycleOptions
  { forceRecollect :: Maybe Bool
  , dryRun :: Maybe Bool
  , maxItemsPerSource :: Maybe Int
  }

instance FromJSON RunInsightCycleOptions where
  parseJSON =
    withObject "RunInsightCycleOptions" $ \requestObject ->
      RunInsightCycleOptions
        <$> requestObject .:? "forceRecollect"
        <*> requestObject .:? "dryRun"
        <*> requestObject .:? "maxItemsPerSource"

-- | Optional body for @POST \/commands\/run-insight-cycle@.
data RunInsightCycleRequest = RunInsightCycleRequest
  { mode :: Maybe Text
  , targetDate :: Maybe Text
  , sourceTypes :: Maybe [Text]
  , options :: Maybe RunInsightCycleOptions
  }

instance FromJSON RunInsightCycleRequest where
  parseJSON =
    withObject "RunInsightCycleRequest" $ \requestObject ->
      RunInsightCycleRequest
        <$> requestObject .:? "mode"
        <*> requestObject .:? "targetDate"
        <*> requestObject .:? "sourceTypes"
        <*> requestObject .:? "options"

-- ---------------------------------------------------------------------------
-- Response type
-- ---------------------------------------------------------------------------

-- | JSON response for @202 Accepted@ command endpoints.
data CommandAccepted = CommandAccepted
  { accepted :: Bool
  , identifier :: Text
  , trace :: Text
  }

instance ToJSON CommandAccepted where
  toJSON commandAccepted =
    object
      [ "accepted" .= commandAccepted.accepted
      , "identifier" .= commandAccepted.identifier
      , "trace" .= commandAccepted.trace
      ]

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

{- | @POST \/commands\/run-cycle@ handler.

Requires @commands:run@ permission. Checks kill switch, then publishes
a @market.collect.requested@ CloudEvent and returns 202.
-}
handleRunCycle ::
  AppEnv ->
  Maybe Text ->
  RunCycleRequest ->
  Handler CommandAccepted
handleRunCycle appEnvironment maybeAuthHeader _request = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "commands:run"

  operationsRuntime <- readOperationsRuntime appEnvironment

  let killSwitchActive = operationsKillSwitchEnabled operationsRuntime
  when killSwitchActive throwKillSwitchEnabled

  now <- liftIO getCurrentTime
  eventIdentifier <- liftIO ULID.getULID
  traceUlid <- liftIO ULID.getULID

  let todayDateText = Text.pack (formatTime defaultTimeLocale "%Y-%m-%d" (utctDay now))
  let publisherEnv =
        PubSubCommandsPublisherEnv
          { publisher = appEnvironment.pubSubPublisher
          , marketCollectTopicName = appEnvironment.marketCollectTopicName
          , insightCollectTopicName = appEnvironment.insightCollectTopicName
          }

  liftIO $
    publishMarketCollectRequested
      publisherEnv
      eventIdentifier
      traceUlid
      now
      todayDateText

  pure
    CommandAccepted
      { accepted = True
      , identifier = Text.pack (show eventIdentifier)
      , trace = Text.pack (show traceUlid)
      }

{- | @POST \/commands\/run-insight-cycle@ handler.

Requires @commands:run@ permission. Checks kill switch, then publishes
an @insight.collect.requested@ CloudEvent and returns 202.
-}
handleRunInsightCycle ::
  AppEnv ->
  Maybe Text ->
  RunInsightCycleRequest ->
  Handler CommandAccepted
handleRunInsightCycle appEnvironment maybeAuthHeader insightRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "commands:run"

  operationsRuntime <- readOperationsRuntime appEnvironment

  let killSwitchActive = operationsKillSwitchEnabled operationsRuntime
  when killSwitchActive throwKillSwitchEnabled

  now <- liftIO getCurrentTime
  eventIdentifier <- liftIO ULID.getULID
  traceUlid <- liftIO ULID.getULID

  let todayDateText = Text.pack (formatTime defaultTimeLocale "%Y-%m-%d" (utctDay now))
  let targetDateText = fromMaybe todayDateText insightRequest.targetDate

  let requestSourceTypes = insightRequest.sourceTypes
  let requestOptions = insightRequest.options

  let maybePublisherOptions =
        requestOptions >>= \o ->
          Just
            InsightCollectOptions
              { forceRecollect = fromMaybe False o.forceRecollect
              , dryRun = fromMaybe False o.dryRun
              , maxItemsPerSource = o.maxItemsPerSource
              }

  let publisherEnv =
        PubSubCommandsPublisherEnv
          { publisher = appEnvironment.pubSubPublisher
          , marketCollectTopicName = appEnvironment.marketCollectTopicName
          , insightCollectTopicName = appEnvironment.insightCollectTopicName
          }

  liftIO $
    publishInsightCollectRequested
      publisherEnv
      eventIdentifier
      traceUlid
      now
      targetDateText
      requestSourceTypes
      maybePublisherOptions

  pure
    CommandAccepted
      { accepted = True
      , identifier = Text.pack (show eventIdentifier)
      , trace = Text.pack (show traceUlid)
      }

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

readOperationsRuntime ::
  AppEnv ->
  Handler OperationsRuntime
readOperationsRuntime appEnvironment = do
  -- 'getOperationsRuntime' internally calls 'Gogol.newEnv' which throws
  -- 'AuthError' (an unchecked exception) when GCP Application Default
  -- Credentials are unavailable (e.g. CI, unit-test environments without
  -- credentials).  Credential/connection failures are a Firestore dependency
  -- outage from the caller's perspective, so we catch all 'SomeException'
  -- here and map them to 503 DEPENDENCY_UNAVAILABLE, preventing 'AuthError'
  -- from propagating as an uncaught exception.
  eitherResult <-
    liftIO $
      try @SomeException $
        getOperationsRuntime
          FirestoreOperationsRepositoryEnv
            { firestoreContext = appEnvironment.firestoreContext
            }
  case eitherResult of
    Left exception -> throwServiceUnavailable ("Firestore unavailable: " <> Text.pack (show exception))
    Right (Left firestoreError) -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right (Right runtimeValue) -> pure runtimeValue

requireAuth :: AppEnv -> Maybe Text -> Text -> Handler VerifiedClaims
requireAuth appEnvironment maybeAuthHeader requiredPermission = do
  rawToken <- extractBearerToken maybeAuthHeader
  let jwtVerifierEnvironment = JwtVerifierEnv{issuerEnv = appEnvironment.jwtIssuerEnv}
  claimsResult <- liftIO $ verifyToken jwtVerifierEnvironment rawToken
  verifiedClaimsValue <- case claimsResult of
    Left verificationError -> throwUnauthorized ("Invalid token: " <> verificationError)
    Right claimsValue -> pure claimsValue
  let hasPermission = requiredPermission `elem` verifiedClaimsValue.permissionClaims
  unless hasPermission $
    throwForbidden ("Missing required permission: " <> requiredPermission)
  pure verifiedClaimsValue

extractBearerToken :: Maybe Text -> Handler Text
extractBearerToken Nothing =
  throwUnauthorized "Authorization header is required"
extractBearerToken (Just headerValue) =
  case Text.stripPrefix "Bearer " headerValue of
    Nothing -> throwUnauthorized "Authorization header must use Bearer scheme"
    Just tokenText -> pure tokenText

throwKillSwitchEnabled :: Handler a
throwKillSwitchEnabled =
  throwError
    err409
      { errBody =
          encode
            ( problemJson
                "Conflict"
                409
                "Kill switch is enabled; command execution is blocked"
                "KILL_SWITCH_ENABLED"
            )
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Conflict"
      }

throwUnauthorized :: Text -> Handler a
throwUnauthorized detailText =
  throwError
    err401
      { errBody = encode (problemJson "Unauthorized" 401 detailText "AUTH_INVALID_CREDENTIALS")
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Unauthorized"
      }

throwForbidden :: Text -> Handler a
throwForbidden detailText =
  throwError
    err403
      { errBody = encode (problemJson "Forbidden" 403 detailText "AUTH_FORBIDDEN")
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Forbidden"
      }

throwServiceUnavailable :: Text -> Handler a
throwServiceUnavailable detailText =
  throwError
    err503
      { errBody = encode (problemJson "Service Unavailable" 503 detailText "DEPENDENCY_UNAVAILABLE")
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Service Unavailable"
      }

data ProblemJson = ProblemJson
  { problemTitle :: Text
  , problemStatus :: Int
  , problemDetail :: Text
  , problemReasonCode :: Text
  }

instance ToJSON ProblemJson where
  toJSON problemValue =
    object
      [ "type" .= ("about:blank" :: Text)
      , "title" .= problemValue.problemTitle
      , "status" .= problemValue.problemStatus
      , "detail" .= problemValue.problemDetail
      , "reasonCode" .= problemValue.problemReasonCode
      ]

problemJson :: Text -> Int -> Text -> Text -> ProblemJson
problemJson titleText statusCode detailText reasonCodeText =
  ProblemJson
    { problemTitle = titleText
    , problemStatus = statusCode
    , problemDetail = detailText
    , problemReasonCode = reasonCodeText
    }

firestoreErrorToText :: FirestoreError -> Text
firestoreErrorToText (FirestoreErrorDecode messageText) = "Decode error: " <> messageText
firestoreErrorToText (FirestoreErrorPermissionDenied messageText) = "Permission denied: " <> messageText
firestoreErrorToText (FirestoreErrorTransport messageText) = "Transport error: " <> messageText
firestoreErrorToText (FirestoreErrorUnexpected statusCode messageText) =
  "Unexpected error " <> Text.pack (show statusCode) <> ": " <> messageText
