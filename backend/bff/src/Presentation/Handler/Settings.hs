module Presentation.Handler.Settings (
  StrategySettingsResponse (..),
  ComplianceControlsResponse (..),
  StrategySettingsUpdateRequest (..),
  ComplianceControlsUpdateRequest (..),
  UpdateResult (..),
  getSettingsStrategyHandler,
  getComplianceControlsHandler,
  putSettingsStrategyHandler,
  putComplianceControlsHandler,
)
where

import Control.Exception (SomeException, try)
import Control.Monad (unless, when)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (FromJSON (..), ToJSON (..), encode, object, withObject, (.:), (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Data.ULID qualified as ULID
import Domain.Compliance.Controls (ComplianceControls (..))
import Domain.Settings.Strategy (
  RebalanceFrequency (..),
  StrategySettings (..),
  rebalanceFrequencyToText,
 )
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Repository.FirestoreSettingsRepository (
  ComplianceControlsUpdate (..),
  FirestoreSettingsRepositoryEnv (..),
  StoredComplianceControls (..),
  StoredStrategySettings (..),
  StrategySettingsUpdate (..),
  getComplianceControls,
  getStoredComplianceControls,
  getStoredStrategySettings,
  getStrategySettings,
  updateComplianceControls,
  updateStrategySettings,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err400, err401, err403, err503, throwError)

-- ---------------------------------------------------------------------------
-- Response types
-- ---------------------------------------------------------------------------

-- | JSON response for @GET \/settings\/strategy@.
data StrategySettingsResponse = StrategySettingsResponse
  { market :: Text
  , rebalanceFrequency :: Text
  , symbols :: [Text]
  , dailyLossLimit :: Double
  , positionConcentrationLimit :: Double
  , dailyOrderLimit :: Int
  }

instance ToJSON StrategySettingsResponse where
  toJSON settingsResponse =
    object
      [ "market" .= settingsResponse.market
      , "rebalanceFrequency" .= settingsResponse.rebalanceFrequency
      , "symbols" .= settingsResponse.symbols
      , "dailyLossLimit" .= settingsResponse.dailyLossLimit
      , "positionConcentrationLimit" .= settingsResponse.positionConcentrationLimit
      , "dailyOrderLimit" .= settingsResponse.dailyOrderLimit
      ]

{- | JSON response for @GET \/compliance\/controls@.

MVP: @blackoutWindows@ and @sourcePolicies@ are always empty arrays.
-}
data ComplianceControlsResponse = ComplianceControlsResponse
  { restrictedSymbols :: [Text]
  , partnerRestrictedSymbols :: [Text]
  , maxCommentLength :: Int
  , autoPromotionEnabled :: Bool
  }

instance ToJSON ComplianceControlsResponse where
  toJSON controlsResponse =
    object
      [ "restrictedSymbols" .= controlsResponse.restrictedSymbols
      , "partnerRestrictedSymbols" .= controlsResponse.partnerRestrictedSymbols
      , "blackoutWindows" .= ([] :: [Text])
      , "sourcePolicies" .= ([] :: [Text])
      , "maxCommentLength" .= controlsResponse.maxCommentLength
      , "autoPromotionEnabled" .= controlsResponse.autoPromotionEnabled
      ]

-- ---------------------------------------------------------------------------
-- Request types
-- ---------------------------------------------------------------------------

-- | JSON request body for @PUT \/settings\/strategy@.
data StrategySettingsUpdateRequest = StrategySettingsUpdateRequest
  { market :: Text
  , rebalanceFrequency :: Text
  , symbols :: [Text]
  , dailyLossLimit :: Double
  , positionConcentrationLimit :: Double
  , dailyOrderLimit :: Int
  }

instance FromJSON StrategySettingsUpdateRequest where
  parseJSON =
    withObject "StrategySettingsUpdateRequest" $ \requestObject ->
      StrategySettingsUpdateRequest
        <$> requestObject .: "market"
        <*> requestObject .: "rebalanceFrequency"
        <*> requestObject .: "symbols"
        <*> requestObject .: "dailyLossLimit"
        <*> requestObject .: "positionConcentrationLimit"
        <*> requestObject .: "dailyOrderLimit"

-- | JSON request body for @PUT \/compliance\/controls@.
data ComplianceControlsUpdateRequest = ComplianceControlsUpdateRequest
  { restrictedSymbols :: [Text]
  , partnerRestrictedSymbols :: [Text]
  , maxCommentLength :: Int
  , autoPromotionEnabled :: Bool
  }

instance FromJSON ComplianceControlsUpdateRequest where
  parseJSON =
    withObject "ComplianceControlsUpdateRequest" $ \requestObject ->
      ComplianceControlsUpdateRequest
        <$> requestObject .: "restrictedSymbols"
        <*> requestObject .: "partnerRestrictedSymbols"
        <*> requestObject .: "maxCommentLength"
        <*> requestObject .: "autoPromotionEnabled"

-- | JSON response for successful update operations.
data UpdateResult = UpdateResult
  { success :: Bool
  , trace :: Text
  }

instance ToJSON UpdateResult where
  toJSON updateResult =
    object
      [ "success" .= updateResult.success
      , "trace" .= updateResult.trace
      ]

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

{- | @GET \/settings\/strategy@ handler.

Requires @settings:read@ permission.
-}
getSettingsStrategyHandler ::
  AppEnv ->
  Maybe Text ->
  Handler StrategySettingsResponse
getSettingsStrategyHandler appEnvironment maybeAuthHeader = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "settings:read"

  settingsResult <-
    liftIO $
      withFirestoreGuard $
        getStrategySettings
          FirestoreSettingsRepositoryEnv
            { firestoreContext = appEnvironment.firestoreContext
            }

  strategySettings <- case settingsResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right settingsValue -> pure settingsValue

  pure
    StrategySettingsResponse
      { market = strategySettings.market
      , rebalanceFrequency = rebalanceFrequencyToText strategySettings.rebalanceFrequency
      , symbols = strategySettings.symbols
      , dailyLossLimit = strategySettings.dailyLossLimit
      , positionConcentrationLimit = strategySettings.positionConcentrationLimit
      , dailyOrderLimit = strategySettings.dailyOrderLimit
      }

{- | @PUT \/settings\/strategy@ handler.

Requires @settings:write@ permission. Validates the request body, reads the
current version counter for optimistic concurrency, and writes updated settings
to @settings\/strategy@.
-}
putSettingsStrategyHandler ::
  AppEnv ->
  Maybe Text ->
  StrategySettingsUpdateRequest ->
  Handler UpdateResult
putSettingsStrategyHandler appEnvironment maybeAuthHeader settingsRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "settings:write"

  validatedSettings <- validateStrategySettingsRequest settingsRequest

  let repositoryEnv = FirestoreSettingsRepositoryEnv{firestoreContext = appEnvironment.firestoreContext}

  storedResult <-
    liftIO $
      withFirestoreGuard $
        getStoredStrategySettings repositoryEnv

  storedSettings <- case storedResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right storedValue -> pure storedValue

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID

  let settingsUpdate =
        StrategySettingsUpdate
          { settings = validatedSettings
          , updatedBy = "bff"
          , updatedAt = now
          , version = storedSettings.version + 1
          }

  updateResult <-
    liftIO $
      withFirestoreGuard $
        updateStrategySettings repositoryEnv settingsUpdate

  case updateResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right () -> pure ()

  pure
    UpdateResult
      { success = True
      , trace = Text.pack (show traceUlid)
      }

{- | @GET \/compliance\/controls@ handler.

Requires @compliance:read@ permission.  MVP: @blackoutWindows@ and
@sourcePolicies@ are returned as empty arrays (stored as complex nested maps
in Firestore that require dedicated FromFirestore instances to decode).
-}
getComplianceControlsHandler ::
  AppEnv ->
  Maybe Text ->
  Handler ComplianceControlsResponse
getComplianceControlsHandler appEnvironment maybeAuthHeader = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "compliance:read"

  controlsResult <-
    liftIO $
      withFirestoreGuard $
        getComplianceControls
          FirestoreSettingsRepositoryEnv
            { firestoreContext = appEnvironment.firestoreContext
            }

  complianceControls <- case controlsResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right controlsValue -> pure controlsValue

  pure
    ComplianceControlsResponse
      { restrictedSymbols = complianceControls.restrictedSymbols
      , partnerRestrictedSymbols = complianceControls.partnerRestrictedSymbols
      , maxCommentLength = complianceControls.maxCommentLength
      , autoPromotionEnabled = complianceControls.autoPromotionEnabled
      }

{- | @PUT \/compliance\/controls@ handler.

Requires @compliance:write@ permission. Validates the request body, reads the
current version counter for optimistic concurrency, and writes updated controls
to @compliance_controls\/trading@.
-}
putComplianceControlsHandler ::
  AppEnv ->
  Maybe Text ->
  ComplianceControlsUpdateRequest ->
  Handler UpdateResult
putComplianceControlsHandler appEnvironment maybeAuthHeader controlsRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "compliance:write"

  validatedControls <- validateComplianceControlsRequest controlsRequest

  let repositoryEnv = FirestoreSettingsRepositoryEnv{firestoreContext = appEnvironment.firestoreContext}

  storedResult <-
    liftIO $
      withFirestoreGuard $
        getStoredComplianceControls repositoryEnv

  storedControls <- case storedResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right storedValue -> pure storedValue

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID

  let controlsUpdate =
        ComplianceControlsUpdate
          { controls = validatedControls
          , updatedBy = "bff"
          , updatedAt = now
          , version = storedControls.version + 1
          }

  updateResult <-
    liftIO $
      withFirestoreGuard $
        updateComplianceControls repositoryEnv controlsUpdate

  case updateResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right () -> pure ()

  pure
    UpdateResult
      { success = True
      , trace = Text.pack (show traceUlid)
      }

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

validateStrategySettingsRequest ::
  StrategySettingsUpdateRequest ->
  Handler StrategySettings
validateStrategySettingsRequest settingsRequest = do
  unless (settingsRequest.market == "JP") $
    throwBadRequest "market must be JP"
  frequencyValue <- case settingsRequest.rebalanceFrequency of
    "daily" -> pure Daily
    "weekly" -> pure Weekly
    other -> throwBadRequest ("rebalanceFrequency must be daily or weekly, got: " <> other)
  when (null settingsRequest.symbols) $
    throwBadRequest "symbols must not be empty"
  unless (settingsRequest.dailyLossLimit >= 0 && settingsRequest.dailyLossLimit <= 20) $
    throwBadRequest "dailyLossLimit must be between 0 and 20"
  unless (settingsRequest.positionConcentrationLimit >= 0 && settingsRequest.positionConcentrationLimit <= 50) $
    throwBadRequest "positionConcentrationLimit must be between 0 and 50"
  unless (settingsRequest.dailyOrderLimit >= 1 && settingsRequest.dailyOrderLimit <= 100) $
    throwBadRequest "dailyOrderLimit must be between 1 and 100"
  pure
    StrategySettings
      { market = settingsRequest.market
      , rebalanceFrequency = frequencyValue
      , symbols = settingsRequest.symbols
      , dailyLossLimit = settingsRequest.dailyLossLimit
      , positionConcentrationLimit = settingsRequest.positionConcentrationLimit
      , dailyOrderLimit = settingsRequest.dailyOrderLimit
      }

validateComplianceControlsRequest ::
  ComplianceControlsUpdateRequest ->
  Handler ComplianceControls
validateComplianceControlsRequest controlsRequest = do
  unless (controlsRequest.maxCommentLength >= 32 && controlsRequest.maxCommentLength <= 240) $
    throwBadRequest "maxCommentLength must be between 32 and 240"
  pure
    ComplianceControls
      { restrictedSymbols = controlsRequest.restrictedSymbols
      , partnerRestrictedSymbols = controlsRequest.partnerRestrictedSymbols
      , maxCommentLength = controlsRequest.maxCommentLength
      , autoPromotionEnabled = controlsRequest.autoPromotionEnabled
      }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

{- | Wrap a Firestore IO action so that any unchecked exception (e.g.
'Gogol.newEnv' 'AuthError' when GCP credentials are absent) is caught and
mapped to 'FirestoreErrorTransport', preventing the server from crashing.
-}
withFirestoreGuard :: IO (Either FirestoreError a) -> IO (Either FirestoreError a)
withFirestoreGuard action = do
  resultEither <- tryAction action
  pure $ case resultEither of
    Left exception -> Left (FirestoreErrorTransport (Text.pack (show exception)))
    Right value -> value
 where
  tryAction :: IO b -> IO (Either SomeException b)
  tryAction = try

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

throwBadRequest :: Text -> Handler a
throwBadRequest detailText =
  throwError
    err400
      { errBody = encode (problemJson "Bad Request" 400 detailText "REQUEST_VALIDATION_FAILED")
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Bad Request"
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
firestoreErrorToText (FirestoreErrorDecode message) = "Decode error: " <> message
firestoreErrorToText (FirestoreErrorPermissionDenied message) = "Permission denied: " <> message
firestoreErrorToText (FirestoreErrorTransport message) = "Transport error: " <> message
firestoreErrorToText (FirestoreErrorUnexpected statusCode message) =
  "Unexpected error " <> Text.pack (show statusCode) <> ": " <> message
