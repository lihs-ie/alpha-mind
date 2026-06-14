module Presentation.Handler.Operations (
  OperationResult (..),
  RuntimeOperationRequest (..),
  KillSwitchRequest (..),
  handleChangeRuntime,
  handleToggleKillSwitch,
) where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (
  FromJSON (..),
  ToJSON (..),
  encode,
  object,
  withObject,
  (.:),
  (.:?),
  (.=),
 )
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Data.ULID qualified as ULID
import Domain.Operation.Control (
  RuntimeAction (..),
  RuntimeTransitionError (..),
  applyKillSwitch,
  validateRuntimeTransition,
 )
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Publisher.PubSubOperationsPublisher (
  PubSubOperationsPublisherEnv (..),
  publishKillSwitchChanged,
 )
import Infrastructure.Repository.FirestoreOperationsRepository (
  FirestoreOperationsRepositoryEnv (..),
  OperationsUpdate (..),
  getOperationsRuntime,
  operationsKillSwitchEnabled,
  operationsRuntimeState,
  operationsVersion,
  updateOperationsRuntime,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err400, err401, err403, err409, err503, throwError)

-- ---------------------------------------------------------------------------
-- Request types
-- ---------------------------------------------------------------------------

data RuntimeOperationRequest = RuntimeOperationRequest
  { action :: Text
  -- ^ Must be @\"START\"@ or @\"STOP\"@.
  , reason :: Maybe Text
  }

instance FromJSON RuntimeOperationRequest where
  parseJSON =
    withObject "RuntimeOperationRequest" $ \requestObject ->
      RuntimeOperationRequest
        <$> requestObject .: "action"
        <*> requestObject .:? "reason"

data KillSwitchRequest = KillSwitchRequest
  { enabled :: Bool
  , actionReasonCode :: Maybe Text
  , comment :: Maybe Text
  }

instance FromJSON KillSwitchRequest where
  parseJSON =
    withObject "KillSwitchRequest" $ \requestObject ->
      KillSwitchRequest
        <$> requestObject .: "enabled"
        <*> requestObject .:? "actionReasonCode"
        <*> requestObject .:? "comment"

-- ---------------------------------------------------------------------------
-- Response type
-- ---------------------------------------------------------------------------

data OperationResult = OperationResult
  { success :: Bool
  , trace :: Text
  , message :: Maybe Text
  }

instance ToJSON OperationResult where
  toJSON operationResult =
    object
      [ "success" .= operationResult.success
      , "trace" .= operationResult.trace
      , "message" .= operationResult.message
      ]

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

{- | @POST \/operations\/runtime@ handler.

Requires @operations:write@ permission. Changes the runtime state
(RUNNING \<-\> STOPPED) with optimistic concurrency via a version counter.
-}
handleChangeRuntime ::
  AppEnv ->
  Maybe Text ->
  RuntimeOperationRequest ->
  Handler OperationResult
handleChangeRuntime appEnvironment maybeAuthHeader runtimeRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "operations:write"

  runtimeAction <- parseRuntimeAction runtimeRequest.action

  currentRuntimeResult <-
    liftIO $
      getOperationsRuntime
        FirestoreOperationsRepositoryEnv
          { firestoreContext = appEnvironment.firestoreContext
          }

  operationsRuntime <- case currentRuntimeResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right runtimeValue -> pure runtimeValue

  let currentRuntimeState = operationsRuntimeState operationsRuntime
      currentKillSwitchEnabled = operationsKillSwitchEnabled operationsRuntime
      currentVersion = operationsVersion operationsRuntime

  newRuntimeState <- case validateRuntimeTransition currentRuntimeState runtimeAction of
    Left (StateConflict messageText) -> throwStateConflict messageText
    Left (OperationNotAllowed messageText) -> throwStateConflict messageText
    Right nextState -> pure nextState

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID

  let operationsUpdate =
        OperationsUpdate
          { runtimeState = newRuntimeState
          , killSwitchEnabled = currentKillSwitchEnabled
          , updatedBy = "bff"
          , updatedAt = now
          , version = currentVersion + 1
          }

  updateResult <-
    liftIO $
      updateOperationsRuntime
        FirestoreOperationsRepositoryEnv
          { firestoreContext = appEnvironment.firestoreContext
          }
        operationsUpdate

  case updateResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right () -> pure ()

  pure
    OperationResult
      { success = True
      , trace = Text.pack (show traceUlid)
      , message = Nothing
      }

{- | @POST \/operations\/kill-switch@ handler.

Requires @operations:write@ permission. Toggles the kill switch and
publishes a @operation.kill_switch.changed@ CloudEvent.
-}
handleToggleKillSwitch ::
  AppEnv ->
  Maybe Text ->
  KillSwitchRequest ->
  Handler OperationResult
handleToggleKillSwitch appEnvironment maybeAuthHeader killSwitchRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "operations:write"

  currentRuntimeResult <-
    liftIO $
      getOperationsRuntime
        FirestoreOperationsRepositoryEnv
          { firestoreContext = appEnvironment.firestoreContext
          }

  operationsRuntime <- case currentRuntimeResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right runtimeValue -> pure runtimeValue

  let currentRuntimeState = operationsRuntimeState operationsRuntime
      currentVersion = operationsVersion operationsRuntime
      newEnabledValue = killSwitchRequest.enabled
      _newKillSwitchState = applyKillSwitch newEnabledValue

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID
  eventIdentifier <- liftIO ULID.getULID

  let operationsUpdate =
        OperationsUpdate
          { runtimeState = currentRuntimeState
          , killSwitchEnabled = newEnabledValue
          , updatedBy = "bff"
          , updatedAt = now
          , version = currentVersion + 1
          }

  updateResult <-
    liftIO $
      updateOperationsRuntime
        FirestoreOperationsRepositoryEnv
          { firestoreContext = appEnvironment.firestoreContext
          }
        operationsUpdate

  case updateResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right () -> pure ()

  let publisherEnv =
        PubSubOperationsPublisherEnv
          { publisher = appEnvironment.pubSubPublisher
          , killSwitchTopicName = appEnvironment.killSwitchTopicName
          }

  liftIO $
    publishKillSwitchChanged
      publisherEnv
      eventIdentifier
      traceUlid
      now
      newEnabledValue

  pure
    OperationResult
      { success = True
      , trace = Text.pack (show traceUlid)
      , message = Nothing
      }

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

parseRuntimeAction :: Text -> Handler RuntimeAction
parseRuntimeAction "START" = pure Start
parseRuntimeAction "STOP" = pure Stop
parseRuntimeAction unknownAction =
  throwError
    err400
      { errBody =
          encode
            ( problemJson
                "Bad Request"
                400
                ("Unknown action: " <> unknownAction <> ". Must be START or STOP")
                "REQUEST_VALIDATION_FAILED"
            )
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Bad Request"
      }

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

throwStateConflict :: Text -> Handler a
throwStateConflict detailText =
  throwError
    err409
      { errBody = encode (problemJson "Conflict" 409 detailText "STATE_CONFLICT")
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Conflict"
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
