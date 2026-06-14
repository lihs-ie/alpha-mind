module Presentation.Handler.ModelValidations (
  ModelValidationSummaryResponse (..),
  ModelValidationDetailResponse (..),
  ModelValidationListResponse (..),
  ModelMetricsResponse (..),
  getModelValidationsHandler,
  getModelValidationByVersionHandler,
)
where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (ToJSON (..), encode, object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Domain.ModelValidation.Record (
  ModelMetrics (..),
  ModelValidationDetail (..),
  ModelValidationSummary (..),
  degradationFlagToText,
  modelValidationStatusToText,
 )
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Repository.FirestoreModelValidationRepository (
  FirestoreModelValidationRepositoryEnv (..),
  ModelValidationQueryFilter (..),
  getModelValidationByVersion,
  listModelValidations,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err400, err401, err403, err404, err503, throwError)

-- ---------------------------------------------------------------------------
-- Response types
-- ---------------------------------------------------------------------------

-- | JSON representation of a model validation summary list item.
data ModelValidationSummaryResponse = ModelValidationSummaryResponse
  { modelVersion :: Text
  , status :: Text
  , degradationFlag :: Text
  , createdAt :: Text
  }

instance ToJSON ModelValidationSummaryResponse where
  toJSON modelValidationSummaryResponse =
    object
      [ "modelVersion" .= modelValidationSummaryResponse.modelVersion
      , "status" .= modelValidationSummaryResponse.status
      , "degradationFlag" .= modelValidationSummaryResponse.degradationFlag
      , "createdAt" .= modelValidationSummaryResponse.createdAt
      ]

-- | JSON representation of model evaluation metrics.
data ModelMetricsResponse = ModelMetricsResponse
  { oosReturn :: Double
  , sharpe :: Double
  , maxDrawdown :: Double
  , turnover :: Double
  , pbo :: Double
  , dsr :: Double
  , costAdjustedReturn :: Double
  , slippageAdjustedSharpe :: Double
  }

instance ToJSON ModelMetricsResponse where
  toJSON modelMetricsResponse =
    object
      [ "oosReturn" .= modelMetricsResponse.oosReturn
      , "sharpe" .= modelMetricsResponse.sharpe
      , "maxDrawdown" .= modelMetricsResponse.maxDrawdown
      , "turnover" .= modelMetricsResponse.turnover
      , "pbo" .= modelMetricsResponse.pbo
      , "dsr" .= modelMetricsResponse.dsr
      , "costAdjustedReturn" .= modelMetricsResponse.costAdjustedReturn
      , "slippageAdjustedSharpe" .= modelMetricsResponse.slippageAdjustedSharpe
      ]

-- | JSON representation of a model validation detail.
data ModelValidationDetailResponse = ModelValidationDetailResponse
  { modelVersion :: Text
  , status :: Text
  , degradationFlag :: Text
  , createdAt :: Text
  , metrics :: ModelMetricsResponse
  , requiresComplianceReview :: Maybe Bool
  }

instance ToJSON ModelValidationDetailResponse where
  toJSON modelValidationDetailResponse =
    object
      [ "modelVersion" .= modelValidationDetailResponse.modelVersion
      , "status" .= modelValidationDetailResponse.status
      , "degradationFlag" .= modelValidationDetailResponse.degradationFlag
      , "createdAt" .= modelValidationDetailResponse.createdAt
      , "metrics" .= modelValidationDetailResponse.metrics
      , "requiresComplianceReview" .= modelValidationDetailResponse.requiresComplianceReview
      ]

-- | Paginated list of model validation summaries.
data ModelValidationListResponse = ModelValidationListResponse
  { items :: [ModelValidationSummaryResponse]
  , nextCursor :: Maybe Text
  }

instance ToJSON ModelValidationListResponse where
  toJSON modelValidationListResponse =
    object
      [ "items" .= modelValidationListResponse.items
      , "nextCursor" .= modelValidationListResponse.nextCursor
      ]

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

{- | @GET \/models\/validation@ handler.

Requires @models:read@ permission.  MVP: status and degradationFlag filters
are accepted but not applied at the Firestore level.
-}
getModelValidationsHandler ::
  AppEnv ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  Maybe Int ->
  Maybe Text ->
  Handler ModelValidationListResponse
getModelValidationsHandler
  appEnvironment
  maybeAuthHeader
  maybeStatus
  _maybeDegradationFlag
  maybeLimit
  _maybeCursor = do
    _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "models:read"

    case maybeStatus of
      Nothing -> pure ()
      Just statusText ->
        let validStatuses = ["candidate", "approved", "rejected"] :: [Text]
         in if statusText `elem` validStatuses
              then pure ()
              else throwBadRequest ("status must be one of: " <> Text.intercalate ", " validStatuses)

    limitValue <- case maybeLimit of
      Nothing -> pure 20
      Just providedLimit ->
        if providedLimit < 1 || providedLimit > 200
          then throwBadRequest "limit must be between 1 and 200"
          else pure providedLimit

    let modelValidationQueryFilter =
          ModelValidationQueryFilter
            { statusFilter = maybeStatus
            , limitCount = limitValue
            }

    listResult <-
      liftIO $
        listModelValidations
          FirestoreModelValidationRepositoryEnv
            { firestoreContext = appEnvironment.firestoreContext
            }
          modelValidationQueryFilter

    modelValidationSummaries <- case listResult of
      Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
      Right items -> pure items

    pure
      ModelValidationListResponse
        { items = map toModelValidationSummaryResponse modelValidationSummaries
        , nextCursor = Nothing
        }

{- | @GET \/models\/validation\/{modelVersion}@ handler.

Requires @models:read@ permission.  Returns 404 when the entry does not exist.
-}
getModelValidationByVersionHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  Handler ModelValidationDetailResponse
getModelValidationByVersionHandler appEnvironment modelVersionParam maybeAuthHeader = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "models:read"

  detailResult <-
    liftIO $
      getModelValidationByVersion
        FirestoreModelValidationRepositoryEnv
          { firestoreContext = appEnvironment.firestoreContext
          }
        modelVersionParam

  maybeDetail <- case detailResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right maybeValue -> pure maybeValue

  case maybeDetail of
    Nothing ->
      throwNotFound "Model validation entry not found"
    Just modelValidationDetail -> pure (toModelValidationDetailResponse modelValidationDetail)

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

throwNotFound :: Text -> Handler a
throwNotFound detailText =
  throwError
    err404
      { errBody = encode (problemJson "Not Found" 404 detailText "RESOURCE_NOT_FOUND")
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Not Found"
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

toModelValidationSummaryResponse :: ModelValidationSummary -> ModelValidationSummaryResponse
toModelValidationSummaryResponse modelValidationSummary =
  ModelValidationSummaryResponse
    { modelVersion = modelValidationSummary.modelVersion
    , status = modelValidationStatusToText modelValidationSummary.status
    , degradationFlag = degradationFlagToText modelValidationSummary.degradationFlag
    , createdAt = Text.pack (show modelValidationSummary.createdAt)
    }

toModelValidationDetailResponse :: ModelValidationDetail -> ModelValidationDetailResponse
toModelValidationDetailResponse modelValidationDetail =
  ModelValidationDetailResponse
    { modelVersion = modelValidationDetail.modelVersion
    , status = modelValidationStatusToText modelValidationDetail.status
    , degradationFlag = degradationFlagToText modelValidationDetail.degradationFlag
    , createdAt = Text.pack (show modelValidationDetail.createdAt)
    , metrics = toModelMetricsResponse modelValidationDetail.metrics
    , requiresComplianceReview = modelValidationDetail.requiresComplianceReview
    }

toModelMetricsResponse :: ModelMetrics -> ModelMetricsResponse
toModelMetricsResponse modelMetrics =
  ModelMetricsResponse
    { oosReturn = modelMetrics.oosReturn
    , sharpe = modelMetrics.sharpe
    , maxDrawdown = modelMetrics.maxDrawdown
    , turnover = modelMetrics.turnover
    , pbo = modelMetrics.pbo
    , dsr = modelMetrics.dsr
    , costAdjustedReturn = modelMetrics.costAdjustedReturn
    , slippageAdjustedSharpe = modelMetrics.slippageAdjustedSharpe
    }
