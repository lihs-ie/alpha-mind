module Presentation.Handler.ModelValidations (
  ModelValidationSummaryResponse (..),
  ModelValidationDetailResponse (..),
  ModelValidationListResponse (..),
  ModelMetricsResponse (..),
  ModelActionResult (..),
  ModelDecisionRequest (..),
  getModelValidationsHandler,
  getModelValidationByVersionHandler,
  approveModelValidationHandler,
  rejectModelValidationHandler,
)
where

import Control.Exception (SomeException, try)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (FromJSON (..), ToJSON (..), encode, object, withObject, (.:), (.:?), (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Data.ULID qualified as ULID
import Domain.ModelValidation.Action (
  ModelValidationTransitionError (..),
  validateApprove,
  validateReject,
 )
import Domain.ModelValidation.Record (
  ModelMetrics (..),
  ModelValidationDetail (..),
  ModelValidationStatus (..),
  ModelValidationSummary (..),
  degradationFlagToText,
  modelValidationStatusToText,
 )
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Repository.FirestoreModelValidationRepository (
  FirestoreModelValidationRepositoryEnv (..),
  ModelValidationQueryFilter (..),
  ModelValidationStatusUpdate (..),
  getModelValidationByVersion,
  listModelValidations,
  updateModelValidationStatus,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err400, err401, err403, err404, err409, err503, throwError)

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

{- | Request body for @POST \/models\/validation\/{modelVersion}\/approve@ and
  @POST \/models\/validation\/{modelVersion}\/reject@.
-}
data ModelDecisionRequest = ModelDecisionRequest
  { actionReasonCode :: Text
  , comment :: Maybe Text
  }

instance FromJSON ModelDecisionRequest where
  parseJSON =
    withObject "ModelDecisionRequest" $ \requestObject ->
      ModelDecisionRequest
        <$> requestObject .: "actionReasonCode"
        <*> requestObject .:? "comment"

-- | Response body for approve and reject actions (200 OK).
data ModelActionResult = ModelActionResult
  { success :: Bool
  , trace :: Text
  }

instance ToJSON ModelActionResult where
  toJSON modelActionResult =
    object
      [ "success" .= modelActionResult.success
      , "trace" .= modelActionResult.trace
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

{- | @POST \/models\/validation\/{modelVersion}\/approve@ handler.

Requires @models:decide@ permission.  Validates the @candidate → approved@
transition per 状態遷移設計.md §5:

  * status must be @candidate@
  * @requiresComplianceReview@ must not be @true@

Updates Firestore @model_registry@ document status and @decidedAt@.
No Pub\/Sub event is published (no asyncapi channel defined for this transition).
-}
approveModelValidationHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  ModelDecisionRequest ->
  Handler ModelActionResult
approveModelValidationHandler appEnvironment modelVersionParam maybeAuthHeader _decisionRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "models:decide"

  modelValidationDetail <- fetchModelValidationOrNotFound appEnvironment modelVersionParam

  case validateApprove modelValidationDetail.status modelValidationDetail.requiresComplianceReview of
    Left ComplianceReviewRequired ->
      throwConflict
        "Model requires compliance review before approval"
        "COMPLIANCE_REVIEW_REQUIRED"
    Left (InvalidStateTransition currentStatus _action) ->
      throwConflict
        ("Cannot approve model validation in status " <> modelValidationStatusToText currentStatus)
        "STATE_CONFLICT"
    Right () -> pure ()

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID

  let statusUpdate =
        ModelValidationStatusUpdate
          { newStatus = ModelValidationStatusApproved
          , decidedAt = now
          }

  updateResult <-
    liftIO
      ( try
          ( updateModelValidationStatus
              FirestoreModelValidationRepositoryEnv
                { firestoreContext = appEnvironment.firestoreContext
                }
              modelVersionParam
              statusUpdate
          ) ::
          IO (Either SomeException (Either FirestoreError ()))
      )

  case updateResult of
    Left _exception -> throwServiceUnavailable "Failed to update model validation status"
    Right (Left firestoreError) -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right (Right ()) -> pure ()

  pure
    ModelActionResult
      { success = True
      , trace = Text.pack (show traceUlid)
      }

{- | @POST \/models\/validation\/{modelVersion}\/reject@ handler.

Requires @models:decide@ permission.  Validates the @candidate → rejected@
transition per 状態遷移設計.md §5.  @approved@ and @rejected@ are terminal;
any attempt to re-transition returns 409.

Updates Firestore @model_registry@ document status and @decidedAt@.
No Pub\/Sub event is published (no asyncapi channel defined for this transition).
-}
rejectModelValidationHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  ModelDecisionRequest ->
  Handler ModelActionResult
rejectModelValidationHandler appEnvironment modelVersionParam maybeAuthHeader _decisionRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "models:decide"

  modelValidationDetail <- fetchModelValidationOrNotFound appEnvironment modelVersionParam

  case validateReject modelValidationDetail.status of
    Left (InvalidStateTransition currentStatus _action) ->
      throwConflict
        ("Cannot reject model validation in status " <> modelValidationStatusToText currentStatus)
        "STATE_CONFLICT"
    Left _ ->
      throwConflict "Invalid state for reject" "STATE_CONFLICT"
    Right () -> pure ()

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID

  let statusUpdate =
        ModelValidationStatusUpdate
          { newStatus = ModelValidationStatusRejected
          , decidedAt = now
          }

  updateResult <-
    liftIO
      ( try
          ( updateModelValidationStatus
              FirestoreModelValidationRepositoryEnv
                { firestoreContext = appEnvironment.firestoreContext
                }
              modelVersionParam
              statusUpdate
          ) ::
          IO (Either SomeException (Either FirestoreError ()))
      )

  case updateResult of
    Left _exception -> throwServiceUnavailable "Failed to update model validation status"
    Right (Left firestoreError) -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right (Right ()) -> pure ()

  pure
    ModelActionResult
      { success = True
      , trace = Text.pack (show traceUlid)
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

throwConflict :: Text -> Text -> Handler a
throwConflict detailText reasonCodeText =
  throwError
    err409
      { errBody = encode (problemJson "Conflict" 409 detailText reasonCodeText)
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Conflict"
      }

{- | Fetch a model validation by modelVersion, returning 404 if not found or
503 on Firestore error (including credential failures).
-}
fetchModelValidationOrNotFound :: AppEnv -> Text -> Handler ModelValidationDetail
fetchModelValidationOrNotFound appEnvironment modelVersionText = do
  detailResult <-
    liftIO
      ( try
          ( getModelValidationByVersion
              FirestoreModelValidationRepositoryEnv
                { firestoreContext = appEnvironment.firestoreContext
                }
              modelVersionText
          ) ::
          IO (Either SomeException (Either FirestoreError (Maybe ModelValidationDetail)))
      )
  case detailResult of
    Left _exception ->
      throwServiceUnavailable "Failed to read model validation"
    Right (Left firestoreError) ->
      throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right (Right Nothing) ->
      throwError
        err404
          { errBody = encode (problemJson "Not Found" 404 "Model validation entry not found" "RESOURCE_NOT_FOUND")
          , errHeaders = [(hContentType, "application/problem+json")]
          , errReasonPhrase = "Not Found"
          }
    Right (Right (Just modelValidationDetail)) ->
      pure modelValidationDetail

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
