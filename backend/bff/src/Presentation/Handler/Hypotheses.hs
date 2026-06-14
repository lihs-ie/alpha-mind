module Presentation.Handler.Hypotheses (
  HypothesisSummaryResponse (..),
  HypothesisDetailResponse (..),
  HypothesisListResponse (..),
  getHypothesesHandler,
  getHypothesisByIdentifierHandler,
)
where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (ToJSON (..), encode, object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Domain.Hypothesis.Record (
  HypothesisDetail (..),
  HypothesisSummary (..),
  hypothesisInsiderRiskToText,
  hypothesisInstrumentTypeToText,
  hypothesisPromotionModeToText,
  hypothesisStatusToText,
 )
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Repository.FirestoreHypothesisRepository (
  FirestoreHypothesisRepositoryEnv (..),
  HypothesisQueryFilter (..),
  getHypothesisByIdentifier,
  listHypotheses,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err400, err401, err403, err404, err503, throwError)

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
