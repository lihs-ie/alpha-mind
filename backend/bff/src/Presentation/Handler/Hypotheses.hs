module Presentation.Handler.Hypotheses (
  HypothesisSummaryResponse (..),
  HypothesisDetailResponse (..),
  HypothesisListResponse (..),
  HypothesisActionResult (..),
  HypothesisRetestAccepted (..),
  HypothesisDecisionRequest (..),
  HypothesisRejectRequest (..),
  HypothesisMnpiSelfDeclarationUpdateRequest (..),
  getHypothesesHandler,
  getHypothesisByIdentifierHandler,
  promoteHypothesisHandler,
  rejectHypothesisHandler,
  retestHypothesisHandler,
  updateHypothesisMnpiHandler,
)
where

import Control.Exception (SomeException, try)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (FromJSON (..), ToJSON (..), encode, object, withObject, (.:), (.:?), (.=))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Data.ULID qualified as ULID
import Domain.Hypothesis.Action (
  HypothesisTransitionError (..),
  validatePromote,
  validateReject,
  validateRetest,
 )
import Domain.Hypothesis.Record (
  HypothesisDetail (..),
  HypothesisInsiderRisk (..),
  HypothesisInstrumentType (..),
  HypothesisStatus (..),
  HypothesisSummary (..),
  hypothesisInsiderRiskToText,
  hypothesisInstrumentTypeToText,
  hypothesisPromotionModeToText,
  hypothesisStatusToText,
 )
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Publisher.PubSubHypothesisPublisher (
  PubSubHypothesisPublisherEnv (..),
  publishHypothesisPromoted,
  publishHypothesisRejected,
  publishHypothesisRetestRequested,
 )
import Infrastructure.Repository.FirestoreHypothesisRepository (
  FirestoreHypothesisRepositoryEnv (..),
  HypothesisMnpiUpdate (..),
  HypothesisQueryFilter (..),
  HypothesisStatusUpdate (..),
  getHypothesisByIdentifier,
  listHypotheses,
  updateHypothesisMnpi,
  updateHypothesisStatus,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err400, err401, err403, err404, err409, err422, err503, throwError)

-- ---------------------------------------------------------------------------
-- Response types
-- ---------------------------------------------------------------------------

-- | JSON representation of a hypothesis summary item.
data HypothesisSummaryResponse = HypothesisSummaryResponse
  { identifier :: Text
  , symbol :: Text
  , instrumentType :: Text
  , status :: Text
  , title :: Text
  , updatedAt :: Text
  }

instance ToJSON HypothesisSummaryResponse where
  toJSON hypothesisSummaryResponse =
    object
      [ "identifier" .= hypothesisSummaryResponse.identifier
      , "symbol" .= hypothesisSummaryResponse.symbol
      , "instrumentType" .= hypothesisSummaryResponse.instrumentType
      , "status" .= hypothesisSummaryResponse.status
      , "title" .= hypothesisSummaryResponse.title
      , "updatedAt" .= hypothesisSummaryResponse.updatedAt
      ]

-- | JSON representation of a hypothesis detail.
data HypothesisDetailResponse = HypothesisDetailResponse
  { identifier :: Text
  , symbol :: Text
  , instrumentType :: Text
  , status :: Text
  , title :: Text
  , updatedAt :: Text
  , sourceEvidence :: [Text]
  , skillVersion :: Text
  , instructionProfileVersion :: Text
  , costAdjustedReturn :: Maybe Double
  , dsr :: Maybe Double
  , pbo :: Maybe Double
  , demoPeriod :: Maybe Text
  , insiderRisk :: Maybe Text
  , requiresComplianceReview :: Maybe Bool
  , mnpiSelfDeclared :: Maybe Bool
  , autoPromotionEligible :: Maybe Bool
  , promotionMode :: Maybe Text
  , latestFailureSummary :: Maybe Text
  }

instance ToJSON HypothesisDetailResponse where
  toJSON hypothesisDetailResponse =
    object
      [ "identifier" .= hypothesisDetailResponse.identifier
      , "symbol" .= hypothesisDetailResponse.symbol
      , "instrumentType" .= hypothesisDetailResponse.instrumentType
      , "status" .= hypothesisDetailResponse.status
      , "title" .= hypothesisDetailResponse.title
      , "updatedAt" .= hypothesisDetailResponse.updatedAt
      , "sourceEvidence" .= hypothesisDetailResponse.sourceEvidence
      , "skillVersion" .= hypothesisDetailResponse.skillVersion
      , "instructionProfileVersion" .= hypothesisDetailResponse.instructionProfileVersion
      , "costAdjustedReturn" .= hypothesisDetailResponse.costAdjustedReturn
      , "dsr" .= hypothesisDetailResponse.dsr
      , "pbo" .= hypothesisDetailResponse.pbo
      , "demoPeriod" .= hypothesisDetailResponse.demoPeriod
      , "insiderRisk" .= hypothesisDetailResponse.insiderRisk
      , "requiresComplianceReview" .= hypothesisDetailResponse.requiresComplianceReview
      , "mnpiSelfDeclared" .= hypothesisDetailResponse.mnpiSelfDeclared
      , "autoPromotionEligible" .= hypothesisDetailResponse.autoPromotionEligible
      , "promotionMode" .= hypothesisDetailResponse.promotionMode
      , "latestFailureSummary" .= hypothesisDetailResponse.latestFailureSummary
      ]

-- | Paginated list of hypothesis summaries.
data HypothesisListResponse = HypothesisListResponse
  { items :: [HypothesisSummaryResponse]
  , nextCursor :: Maybe Text
  }

instance ToJSON HypothesisListResponse where
  toJSON hypothesisListResponse =
    object
      [ "items" .= hypothesisListResponse.items
      , "nextCursor" .= hypothesisListResponse.nextCursor
      ]

-- | Request body for @POST \/hypotheses\/{identifier}\/promote@.
data HypothesisDecisionRequest = HypothesisDecisionRequest
  { actionReasonCode :: Text
  , comment :: Maybe Text
  , mnpiSelfDeclared :: Bool
  }

instance FromJSON HypothesisDecisionRequest where
  parseJSON =
    withObject "HypothesisDecisionRequest" $ \requestObject ->
      HypothesisDecisionRequest
        <$> requestObject .: "actionReasonCode"
        <*> requestObject .:? "comment"
        <*> requestObject .: "mnpiSelfDeclared"

-- | Request body for @POST \/hypotheses\/{identifier}\/reject@.
data HypothesisRejectRequest = HypothesisRejectRequest
  { actionReasonCode :: Text
  , comment :: Maybe Text
  }

instance FromJSON HypothesisRejectRequest where
  parseJSON =
    withObject "HypothesisRejectRequest" $ \requestObject ->
      HypothesisRejectRequest
        <$> requestObject .: "actionReasonCode"
        <*> requestObject .:? "comment"

-- | Request body for @PUT \/hypotheses\/{identifier}\/mnpi-self-declaration@.
data HypothesisMnpiSelfDeclarationUpdateRequest = HypothesisMnpiSelfDeclarationUpdateRequest
  { mnpiSelfDeclared :: Bool
  , actionReasonCode :: Text
  , comment :: Maybe Text
  }

instance FromJSON HypothesisMnpiSelfDeclarationUpdateRequest where
  parseJSON =
    withObject "HypothesisMnpiSelfDeclarationUpdateRequest" $ \requestObject ->
      HypothesisMnpiSelfDeclarationUpdateRequest
        <$> requestObject .: "mnpiSelfDeclared"
        <*> requestObject .: "actionReasonCode"
        <*> requestObject .:? "comment"

-- | Response body for promote, reject, and mnpi-self-declaration actions (200 OK).
data HypothesisActionResult = HypothesisActionResult
  { success :: Bool
  , trace :: Text
  }

instance ToJSON HypothesisActionResult where
  toJSON actionResult =
    object
      [ "success" .= actionResult.success
      , "trace" .= actionResult.trace
      ]

-- | Response body for retest action (202 Accepted).
data HypothesisRetestAccepted = HypothesisRetestAccepted
  { accepted :: Bool
  , identifier :: Text
  , trace :: Text
  }

instance ToJSON HypothesisRetestAccepted where
  toJSON retestAccepted =
    object
      [ "accepted" .= retestAccepted.accepted
      , "identifier" .= retestAccepted.identifier
      , "trace" .= retestAccepted.trace
      ]

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

{- | @GET \/hypotheses@ handler.

Requires @hypotheses:read@ permission.  MVP: status filter is accepted but not
applied (returns all hypotheses up to limit).
-}
getHypothesesHandler ::
  AppEnv ->
  Maybe Text ->
  Maybe Text ->
  Maybe Int ->
  Maybe Text ->
  Handler HypothesisListResponse
getHypothesesHandler
  appEnvironment
  maybeAuthHeader
  maybeStatus
  maybeLimit
  _maybeCursor = do
    _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "hypotheses:read"

    case maybeStatus of
      Nothing -> pure ()
      Just statusText ->
        let validStatuses = ["draft", "backtested", "demo", "live", "rejected"] :: [Text]
         in if statusText `elem` validStatuses
              then pure ()
              else throwBadRequest ("status must be one of: " <> Text.intercalate ", " validStatuses)

    limitValue <- case maybeLimit of
      Nothing -> pure 30
      Just providedLimit ->
        if providedLimit < 1 || providedLimit > 200
          then throwBadRequest "limit must be between 1 and 200"
          else pure providedLimit

    let hypothesisQueryFilter =
          HypothesisQueryFilter
            { statusFilter = Nothing
            , limitCount = limitValue
            }

    hypothesisResult <-
      liftIO $
        listHypotheses
          FirestoreHypothesisRepositoryEnv
            { firestoreContext = appEnvironment.firestoreContext
            }
          hypothesisQueryFilter

    hypothesisSummaries <- case hypothesisResult of
      Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
      Right hypothesisItems -> pure hypothesisItems

    pure
      HypothesisListResponse
        { items = map toHypothesisSummaryResponse hypothesisSummaries
        , nextCursor = Nothing
        }

{- | @GET \/hypotheses\/{identifier}@ handler.

Requires @hypotheses:read@ permission.  Returns 404 when the hypothesis does not exist.
-}
getHypothesisByIdentifierHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  Handler HypothesisDetailResponse
getHypothesisByIdentifierHandler appEnvironment hypothesisIdentifier maybeAuthHeader = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "hypotheses:read"

  detailResult <-
    liftIO $
      getHypothesisByIdentifier
        FirestoreHypothesisRepositoryEnv
          { firestoreContext = appEnvironment.firestoreContext
          }
        hypothesisIdentifier

  maybeDetail <- case detailResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right maybeValue -> pure maybeValue

  case maybeDetail of
    Nothing ->
      throwNotFound "Hypothesis not found"
    Just hypothesisDetail -> pure (toHypothesisDetailResponse hypothesisDetail)

{- | @POST \/hypotheses\/{identifier}\/promote@ handler.

Requires @hypotheses:decide@ permission.  Validates the @demo → live@
transition per 状態遷移設計.md §6:
  * status must be @demo@
  * @requiresComplianceReview@ must not be @true@
  * @mnpiSelfDeclared@ must be @true@ (from the request body)
  * @instrumentType=ETF@ + @insiderRisk=low@ → promotion mode @auto@
  * otherwise → promotion mode @manual@
Updates Firestore and publishes @hypothesis.promoted@.
-}
promoteHypothesisHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  HypothesisDecisionRequest ->
  Handler HypothesisActionResult
promoteHypothesisHandler appEnvironment hypothesisIdentifier maybeAuthHeader promoteRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "hypotheses:decide"

  unless promoteRequest.mnpiSelfDeclared $
    throwUnprocessableEntity "mnpiSelfDeclared must be true for promotion" "COMPLIANCE_MNPI_SUSPECTED"

  hypothesisDetail <- fetchHypothesisOrNotFound appEnvironment hypothesisIdentifier

  case validatePromote hypothesisDetail.status hypothesisDetail.requiresComplianceReview hypothesisDetail.mnpiSelfDeclared of
    Left ComplianceReviewRequired ->
      throwConflict "Hypothesis requires compliance review before promotion" "COMPLIANCE_REVIEW_REQUIRED"
    Left MnpiSelfDeclarationMissing ->
      throwConflict "MNPI self-declaration must be true before promotion" "COMPLIANCE_MNPI_SUSPECTED"
    Left DemoPeriodInsufficient ->
      throwConflict "Demo period has not reached 30 days" "OPERATION_NOT_ALLOWED"
    Left (InvalidStateTransition currentStatus _action) ->
      throwConflict
        ("Cannot promote hypothesis in status " <> hypothesisStatusToText currentStatus)
        "STATE_CONFLICT"
    Right () -> pure ()

  let promotionModeValue =
        case hypothesisDetail.instrumentType of
          HypothesisInstrumentTypeETF ->
            case hypothesisDetail.insiderRisk of
              Just HypothesisInsiderRiskLow -> "auto"
              _ -> "manual"
          _ -> "manual"

  let insiderRiskValue = maybe "medium" hypothesisInsiderRiskToText hypothesisDetail.insiderRisk

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID
  eventUlid <- liftIO ULID.getULID

  let statusUpdate =
        HypothesisStatusUpdate
          { newStatus = HypothesisStatusLive
          , newPromotionMode = Just promotionModeValue
          , updatedAt = now
          }

  updateResult <-
    liftIO
      ( try
          ( updateHypothesisStatus
              FirestoreHypothesisRepositoryEnv
                { firestoreContext = appEnvironment.firestoreContext
                }
              hypothesisIdentifier
              statusUpdate
          ) ::
          IO (Either SomeException (Either FirestoreError ()))
      )

  case updateResult of
    Left _exception -> throwServiceUnavailable "Failed to update hypothesis status"
    Right (Left firestoreError) -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right (Right ()) -> pure ()

  let publisherEnvironment =
        PubSubHypothesisPublisherEnv
          { publisher = appEnvironment.pubSubPublisher
          , hypothesisPromotedTopicName = appEnvironment.hypothesisPromotedTopicName
          , hypothesisRejectedTopicName = appEnvironment.hypothesisRejectedTopicName
          , hypothesisRetestRequestedTopicName = appEnvironment.hypothesisRetestRequestedTopicName
          }

  liftIO $
    publishHypothesisPromoted
      publisherEnvironment
      eventUlid
      traceUlid
      now
      hypothesisIdentifier
      promoteRequest.actionReasonCode
      promotionModeValue
      True
      insiderRiskValue

  pure
    HypothesisActionResult
      { success = True
      , trace = Text.pack (show traceUlid)
      }

{- | @POST \/hypotheses\/{identifier}\/reject@ handler.

Requires @hypotheses:decide@ permission.  Validates the @demo → rejected@
transition per 状態遷移設計.md §6.  Updates Firestore and publishes
@hypothesis.rejected@.
-}
rejectHypothesisHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  HypothesisRejectRequest ->
  Handler HypothesisActionResult
rejectHypothesisHandler appEnvironment hypothesisIdentifier maybeAuthHeader rejectRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "hypotheses:decide"

  hypothesisDetail <- fetchHypothesisOrNotFound appEnvironment hypothesisIdentifier

  case validateReject hypothesisDetail.status of
    Left (InvalidStateTransition currentStatus _action) ->
      throwConflict
        ("Cannot reject hypothesis in status " <> hypothesisStatusToText currentStatus)
        "STATE_CONFLICT"
    Left _ -> throwConflict "Invalid state for reject" "STATE_CONFLICT"
    Right () -> pure ()

  let insiderRiskValue = maybe "medium" hypothesisInsiderRiskToText hypothesisDetail.insiderRisk

  let mnpiSelfDeclaredValue = fromMaybe False hypothesisDetail.mnpiSelfDeclared

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID
  eventUlid <- liftIO ULID.getULID

  let statusUpdate =
        HypothesisStatusUpdate
          { newStatus = HypothesisStatusRejected
          , newPromotionMode = Nothing
          , updatedAt = now
          }

  updateResult <-
    liftIO
      ( try
          ( updateHypothesisStatus
              FirestoreHypothesisRepositoryEnv
                { firestoreContext = appEnvironment.firestoreContext
                }
              hypothesisIdentifier
              statusUpdate
          ) ::
          IO (Either SomeException (Either FirestoreError ()))
      )

  case updateResult of
    Left _exception -> throwServiceUnavailable "Failed to update hypothesis status"
    Right (Left firestoreError) -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right (Right ()) -> pure ()

  let publisherEnvironment =
        PubSubHypothesisPublisherEnv
          { publisher = appEnvironment.pubSubPublisher
          , hypothesisPromotedTopicName = appEnvironment.hypothesisPromotedTopicName
          , hypothesisRejectedTopicName = appEnvironment.hypothesisRejectedTopicName
          , hypothesisRetestRequestedTopicName = appEnvironment.hypothesisRetestRequestedTopicName
          }

  liftIO $
    publishHypothesisRejected
      publisherEnvironment
      eventUlid
      traceUlid
      now
      hypothesisIdentifier
      rejectRequest.actionReasonCode
      mnpiSelfDeclaredValue
      insiderRiskValue

  pure
    HypothesisActionResult
      { success = True
      , trace = Text.pack (show traceUlid)
      }

{- | @POST \/hypotheses\/{identifier}\/retest@ handler.

Requires @hypotheses:retest@ permission.  Validates that the hypothesis is in
@demo@ or @backtested@ status per 状態遷移設計.md §7.  Does not change Firestore
status; publishes @hypothesis.retest.requested@ and returns 202.
-}
retestHypothesisHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  Handler HypothesisRetestAccepted
retestHypothesisHandler appEnvironment hypothesisIdentifier maybeAuthHeader = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "hypotheses:retest"

  hypothesisDetail <- fetchHypothesisOrNotFound appEnvironment hypothesisIdentifier

  case validateRetest hypothesisDetail.status of
    Left (InvalidStateTransition currentStatus _action) ->
      throwConflict
        ("Cannot request retest for hypothesis in status " <> hypothesisStatusToText currentStatus)
        "STATE_CONFLICT"
    Left _ -> throwConflict "Invalid state for retest" "STATE_CONFLICT"
    Right () -> pure ()

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID
  eventUlid <- liftIO ULID.getULID

  let publisherEnvironment =
        PubSubHypothesisPublisherEnv
          { publisher = appEnvironment.pubSubPublisher
          , hypothesisPromotedTopicName = appEnvironment.hypothesisPromotedTopicName
          , hypothesisRejectedTopicName = appEnvironment.hypothesisRejectedTopicName
          , hypothesisRetestRequestedTopicName = appEnvironment.hypothesisRetestRequestedTopicName
          }

  liftIO $
    publishHypothesisRetestRequested
      publisherEnvironment
      eventUlid
      traceUlid
      now
      hypothesisIdentifier

  pure
    HypothesisRetestAccepted
      { accepted = True
      , identifier = hypothesisIdentifier
      , trace = Text.pack (show traceUlid)
      }

{- | @PUT \/hypotheses\/{identifier}\/mnpi-self-declaration@ handler.

Requires @hypotheses:decide@ permission.  Updates the @mnpiSelfDeclared@
field in @hypothesis_registry@ without changing the hypothesis status.
No event is published (per 状態遷移設計.md §7).
-}
updateHypothesisMnpiHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  HypothesisMnpiSelfDeclarationUpdateRequest ->
  Handler HypothesisActionResult
updateHypothesisMnpiHandler appEnvironment hypothesisIdentifier maybeAuthHeader mnpiRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "hypotheses:decide"

  _hypothesisDetail <- fetchHypothesisOrNotFound appEnvironment hypothesisIdentifier

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID

  let mnpiUpdate =
        HypothesisMnpiUpdate
          { mnpiSelfDeclared = mnpiRequest.mnpiSelfDeclared
          , updatedAt = now
          }

  updateResult <-
    liftIO
      ( try
          ( updateHypothesisMnpi
              FirestoreHypothesisRepositoryEnv
                { firestoreContext = appEnvironment.firestoreContext
                }
              hypothesisIdentifier
              mnpiUpdate
          ) ::
          IO (Either SomeException (Either FirestoreError ()))
      )

  case updateResult of
    Left _exception -> throwServiceUnavailable "Failed to update hypothesis MNPI declaration"
    Right (Left firestoreError) -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right (Right ()) -> pure ()

  pure
    HypothesisActionResult
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

throwUnprocessableEntity :: Text -> Text -> Handler a
throwUnprocessableEntity detailText reasonCodeText =
  throwError
    err422
      { errBody = encode (problemJson "Unprocessable Entity" 422 detailText reasonCodeText)
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Unprocessable Entity"
      }

-- | Fetch a hypothesis by identifier, returning 404 if not found or 503 on Firestore error.
fetchHypothesisOrNotFound :: AppEnv -> Text -> Handler HypothesisDetail
fetchHypothesisOrNotFound appEnvironment hypothesisIdentifier = do
  detailResult <-
    liftIO
      ( try
          ( getHypothesisByIdentifier
              FirestoreHypothesisRepositoryEnv
                { firestoreContext = appEnvironment.firestoreContext
                }
              hypothesisIdentifier
          ) ::
          IO (Either SomeException (Either FirestoreError (Maybe HypothesisDetail)))
      )
  case detailResult of
    Left _exception ->
      throwServiceUnavailable "Failed to read hypothesis"
    Right (Left firestoreError) ->
      throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right (Right Nothing) ->
      throwError
        err404
          { errBody = encode (problemJson "Not Found" 404 "Hypothesis not found" "RESOURCE_NOT_FOUND")
          , errHeaders = [(hContentType, "application/problem+json")]
          , errReasonPhrase = "Not Found"
          }
    Right (Right (Just hypothesisDetail)) ->
      pure hypothesisDetail

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

toHypothesisSummaryResponse :: HypothesisSummary -> HypothesisSummaryResponse
toHypothesisSummaryResponse hypothesisSummary =
  HypothesisSummaryResponse
    { identifier = hypothesisSummary.identifier
    , symbol = hypothesisSummary.symbol
    , instrumentType = hypothesisInstrumentTypeToText hypothesisSummary.instrumentType
    , status = hypothesisStatusToText hypothesisSummary.status
    , title = hypothesisSummary.title
    , updatedAt = Text.pack (show hypothesisSummary.updatedAt)
    }

toHypothesisDetailResponse :: HypothesisDetail -> HypothesisDetailResponse
toHypothesisDetailResponse hypothesisDetail =
  HypothesisDetailResponse
    { identifier = hypothesisDetail.identifier
    , symbol = hypothesisDetail.symbol
    , instrumentType = hypothesisInstrumentTypeToText hypothesisDetail.instrumentType
    , status = hypothesisStatusToText hypothesisDetail.status
    , title = hypothesisDetail.title
    , updatedAt = Text.pack (show hypothesisDetail.updatedAt)
    , sourceEvidence = hypothesisDetail.sourceEvidence
    , skillVersion = hypothesisDetail.skillVersion
    , instructionProfileVersion = hypothesisDetail.instructionProfileVersion
    , costAdjustedReturn = hypothesisDetail.costAdjustedReturn
    , dsr = hypothesisDetail.dsr
    , pbo = hypothesisDetail.pbo
    , demoPeriod = hypothesisDetail.demoPeriod
    , insiderRisk = fmap hypothesisInsiderRiskToText hypothesisDetail.insiderRisk
    , requiresComplianceReview = hypothesisDetail.requiresComplianceReview
    , mnpiSelfDeclared = hypothesisDetail.mnpiSelfDeclared
    , autoPromotionEligible = hypothesisDetail.autoPromotionEligible
    , promotionMode = fmap hypothesisPromotionModeToText hypothesisDetail.promotionMode
    , latestFailureSummary = hypothesisDetail.latestFailureSummary
    }
