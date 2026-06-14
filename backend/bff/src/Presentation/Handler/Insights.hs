module Presentation.Handler.Insights (
  InsightSummaryResponse (..),
  InsightDetailResponse (..),
  InsightListResponse (..),
  getInsightsHandler,
  getInsightByIdentifierHandler,
)
where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (ToJSON (..), encode, object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Domain.Insight.Record (
  InsightDetail (..),
  InsightSummary (..),
  insightSentimentToText,
  insightSignalClassToText,
  insightSourceTypeToText,
 )
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Repository.FirestoreInsightRepository (
  FirestoreInsightRepositoryEnv (..),
  InsightQueryFilter (..),
  getInsightRecordByIdentifier,
  listInsightRecords,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err400, err401, err403, err404, err503, throwError)

-- ---------------------------------------------------------------------------
-- Response types
-- ---------------------------------------------------------------------------

-- | JSON representation of an insight record summary item.
data InsightSummaryResponse = InsightSummaryResponse
  { identifier :: Text
  , sourceType :: Text
  , summary :: Text
  , sourceUrl :: Text
  , collectedAt :: Text
  , signalClass :: Text
  , soWhatScore :: Double
  , skillVersion :: Maybe Text
  }

instance ToJSON InsightSummaryResponse where
  toJSON insightSummaryResponse =
    object
      [ "identifier" .= insightSummaryResponse.identifier
      , "sourceType" .= insightSummaryResponse.sourceType
      , "summary" .= insightSummaryResponse.summary
      , "sourceUrl" .= insightSummaryResponse.sourceUrl
      , "collectedAt" .= insightSummaryResponse.collectedAt
      , "signalClass" .= insightSummaryResponse.signalClass
      , "soWhatScore" .= insightSummaryResponse.soWhatScore
      , "skillVersion" .= insightSummaryResponse.skillVersion
      ]

-- | JSON representation of an insight record detail.
data InsightDetailResponse = InsightDetailResponse
  { identifier :: Text
  , sourceType :: Text
  , summary :: Text
  , sourceUrl :: Text
  , collectedAt :: Text
  , signalClass :: Text
  , soWhatScore :: Double
  , skillVersion :: Maybe Text
  , evidenceSnippet :: Text
  , theme :: Maybe Text
  , sentiment :: Maybe Text
  , trace :: Maybe Text
  }

instance ToJSON InsightDetailResponse where
  toJSON insightDetailResponse =
    object
      [ "identifier" .= insightDetailResponse.identifier
      , "sourceType" .= insightDetailResponse.sourceType
      , "summary" .= insightDetailResponse.summary
      , "sourceUrl" .= insightDetailResponse.sourceUrl
      , "collectedAt" .= insightDetailResponse.collectedAt
      , "signalClass" .= insightDetailResponse.signalClass
      , "soWhatScore" .= insightDetailResponse.soWhatScore
      , "skillVersion" .= insightDetailResponse.skillVersion
      , "evidenceSnippet" .= insightDetailResponse.evidenceSnippet
      , "theme" .= insightDetailResponse.theme
      , "sentiment" .= insightDetailResponse.sentiment
      , "trace" .= insightDetailResponse.trace
      ]

-- | Paginated list of insight record summaries.
data InsightListResponse = InsightListResponse
  { items :: [InsightSummaryResponse]
  , nextCursor :: Maybe Text
  }

instance ToJSON InsightListResponse where
  toJSON insightListResponse =
    object
      [ "items" .= insightListResponse.items
      , "nextCursor" .= insightListResponse.nextCursor
      ]

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

{- | @GET \/insights@ handler.

Requires @insights:read@ permission.  MVP: symbol, from, and to filters are
accepted but not applied (returns all insight records up to limit).
-}
getInsightsHandler ::
  AppEnv ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  Maybe Int ->
  Maybe Text ->
  Handler InsightListResponse
getInsightsHandler
  appEnvironment
  maybeAuthHeader
  _maybeSymbol
  _maybeFrom
  _maybeTo
  maybeLimit
  _maybeCursor = do
    _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "insights:read"

    limitValue <- case maybeLimit of
      Nothing -> pure 50
      Just providedLimit ->
        if providedLimit < 1 || providedLimit > 200
          then throwBadRequest "limit must be between 1 and 200"
          else pure providedLimit

    let insightQueryFilter =
          InsightQueryFilter
            { symbolFilter = Nothing
            , limitCount = limitValue
            }

    insightResult <-
      liftIO $
        listInsightRecords
          FirestoreInsightRepositoryEnv
            { firestoreContext = appEnvironment.firestoreContext
            }
          insightQueryFilter

    insightSummaries <- case insightResult of
      Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
      Right insightItems -> pure insightItems

    pure
      InsightListResponse
        { items = map toInsightSummaryResponse insightSummaries
        , nextCursor = Nothing
        }

{- | @GET \/insights\/{identifier}@ handler.

Requires @insights:read@ permission.  Returns 404 when the record does not exist.
-}
getInsightByIdentifierHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  Handler InsightDetailResponse
getInsightByIdentifierHandler appEnvironment insightIdentifier maybeAuthHeader = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "insights:read"

  detailResult <-
    liftIO $
      getInsightRecordByIdentifier
        FirestoreInsightRepositoryEnv
          { firestoreContext = appEnvironment.firestoreContext
          }
        insightIdentifier

  maybeDetail <- case detailResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right maybeValue -> pure maybeValue

  case maybeDetail of
    Nothing ->
      throwNotFound "Insight record not found"
    Just insightDetail -> pure (toInsightDetailResponse insightDetail)

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

toInsightSummaryResponse :: InsightSummary -> InsightSummaryResponse
toInsightSummaryResponse insightSummary =
  InsightSummaryResponse
    { identifier = insightSummary.identifier
    , sourceType = insightSourceTypeToText insightSummary.sourceType
    , summary = insightSummary.summary
    , sourceUrl = insightSummary.sourceUrl
    , collectedAt = Text.pack (show insightSummary.collectedAt)
    , signalClass = insightSignalClassToText insightSummary.signalClass
    , soWhatScore = insightSummary.soWhatScore
    , skillVersion = insightSummary.skillVersion
    }

toInsightDetailResponse :: InsightDetail -> InsightDetailResponse
toInsightDetailResponse insightDetail =
  InsightDetailResponse
    { identifier = insightDetail.identifier
    , sourceType = insightSourceTypeToText insightDetail.sourceType
    , summary = insightDetail.summary
    , sourceUrl = insightDetail.sourceUrl
    , collectedAt = Text.pack (show insightDetail.collectedAt)
    , signalClass = insightSignalClassToText insightDetail.signalClass
    , soWhatScore = insightDetail.soWhatScore
    , skillVersion = insightDetail.skillVersion
    , evidenceSnippet = insightDetail.evidenceSnippet
    , theme = insightDetail.theme
    , sentiment = fmap insightSentimentToText insightDetail.sentiment
    , trace = insightDetail.trace
    }
