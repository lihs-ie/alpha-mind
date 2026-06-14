module Presentation.Handler.Dashboard (
  DashboardSummaryResponse (..),
  getDashboardSummaryHandler,
)
where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (ToJSON (..), encode, object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Domain.Dashboard.Summary (runtimeStateToText)
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Repository.FirestoreOperationsRepository (
  FirestoreOperationsRepositoryEnv (..),
  OperationsRuntime (..),
  getOperationsRuntime,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err401, err403, err503, throwError)

-- ---------------------------------------------------------------------------
-- Response type
-- ---------------------------------------------------------------------------

-- | Must-01: JSON response matching the @DashboardSummary@ OpenAPI schema.
data DashboardSummaryResponse = DashboardSummaryResponse
  { pnlToday :: Double
  , pnlTotal :: Double
  , maxDrawdown :: Double
  , runtimeState :: Text
  , killSwitchEnabled :: Bool
  , latestSignalAt :: Text
  }

instance ToJSON DashboardSummaryResponse where
  toJSON dashboardResponse =
    object
      [ "pnlToday" .= dashboardResponse.pnlToday
      , "pnlTotal" .= dashboardResponse.pnlTotal
      , "maxDrawdown" .= dashboardResponse.maxDrawdown
      , "runtimeState" .= dashboardResponse.runtimeState
      , "killSwitchEnabled" .= dashboardResponse.killSwitchEnabled
      , "latestSignalAt" .= dashboardResponse.latestSignalAt
      ]

-- ---------------------------------------------------------------------------
-- Handler
-- ---------------------------------------------------------------------------

{- | Must-01 to Must-09: @GET \/dashboard\/summary@ handler.

1. Extracts and verifies the Bearer JWT (Must-02 \/ Must-08).
2. Checks @dashboard:read@ permission (Must-03).
3. Reads @operations\/runtime@ from Firestore (Must-04 \/ Must-07).
4. Assembles @DashboardSummaryResponse@ with MVP placeholders (Must-05).
-}
getDashboardSummaryHandler ::
  AppEnv ->
  Maybe Text ->
  Handler DashboardSummaryResponse
getDashboardSummaryHandler appEnvironment maybeAuthHeader = do
  -- Must-02: Extract Bearer token
  rawToken <- extractBearerToken maybeAuthHeader

  -- Must-08: Verify JWT signature and expiry
  let jwtVerifierEnvironment = JwtVerifierEnv{issuerEnv = appEnvironment.jwtIssuerEnv}
  claimsResult <- liftIO $ verifyToken jwtVerifierEnvironment rawToken
  verifiedClaimsValue <- case claimsResult of
    Left verificationError -> throwUnauthorized ("Invalid token: " <> verificationError)
    Right claimsValue -> pure claimsValue

  -- Must-03: Check dashboard:read permission
  let hasPermission = "dashboard:read" `elem` verifiedClaimsValue.permissionClaims
  unless hasPermission $
    throwForbidden "Missing required permission: dashboard:read"

  -- Must-04: Read operations/runtime from Firestore
  operationsResult <-
    liftIO $
      getOperationsRuntime
        FirestoreOperationsRepositoryEnv
          { firestoreContext = appEnvironment.firestoreContext
          }

  operationsRuntime <- case operationsResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right runtimeValue -> pure runtimeValue

  -- Must-05: MVP placeholders for PnL fields; latestSignalAt = current time
  currentTime <- liftIO getCurrentTime

  pure
    DashboardSummaryResponse
      { pnlToday = 0.0
      , pnlTotal = 0.0
      , maxDrawdown = 0.0
      , runtimeState = runtimeStateToText operationsRuntime.runtimeState
      , killSwitchEnabled = operationsRuntime.killSwitchEnabled
      , latestSignalAt = Text.pack (show currentTime)
      }

-- ---------------------------------------------------------------------------
-- Error helpers
-- ---------------------------------------------------------------------------

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
