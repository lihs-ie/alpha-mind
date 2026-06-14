module Presentation.Handler.Settings (
  StrategySettingsResponse (..),
  ComplianceControlsResponse (..),
  getSettingsStrategyHandler,
  getComplianceControlsHandler,
)
where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (ToJSON (..), encode, object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Domain.Compliance.Controls (ComplianceControls (..))
import Domain.Settings.Strategy (StrategySettings (..), rebalanceFrequencyToText)
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Repository.FirestoreSettingsRepository (
  FirestoreSettingsRepositoryEnv (..),
  getComplianceControls,
  getStrategySettings,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err401, err403, err503, throwError)

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

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

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
