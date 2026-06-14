module Presentation.Handler.Audit (
  AuditSummaryResponse (..),
  AuditDetailResponse (..),
  AuditListResponse (..),
  getAuditLogsHandler,
  getAuditLogByIdentifierHandler,
)
where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (ToJSON (..), encode, object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Domain.Audit.Log (
  AuditDetail (..),
  AuditSummary (..),
  auditResultToText,
 )
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Repository.FirestoreAuditRepository (
  AuditQueryFilter (..),
  FirestoreAuditRepositoryEnv (..),
  getAuditLogByIdentifier,
  listAuditLogs,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err401, err403, err404, err503, throwError)

-- ---------------------------------------------------------------------------
-- Response types
-- ---------------------------------------------------------------------------

-- | JSON representation of an audit log summary item.
data AuditSummaryResponse = AuditSummaryResponse
  { identifier :: Text
  , occurredAt :: Text
  , eventType :: Text
  , service :: Text
  , result :: Text
  , trace :: Text
  }

instance ToJSON AuditSummaryResponse where
  toJSON auditResponse =
    object
      [ "identifier" .= auditResponse.identifier
      , "occurredAt" .= auditResponse.occurredAt
      , "eventType" .= auditResponse.eventType
      , "service" .= auditResponse.service
      , "result" .= auditResponse.result
      , "trace" .= auditResponse.trace
      ]

-- | JSON representation of an audit log detail.
data AuditDetailResponse = AuditDetailResponse
  { identifier :: Text
  , occurredAt :: Text
  , eventType :: Text
  , service :: Text
  , result :: Text
  , trace :: Text
  , reason :: Maybe Text
  }

instance ToJSON AuditDetailResponse where
  toJSON auditDetail =
    object
      [ "identifier" .= auditDetail.identifier
      , "occurredAt" .= auditDetail.occurredAt
      , "eventType" .= auditDetail.eventType
      , "service" .= auditDetail.service
      , "result" .= auditDetail.result
      , "trace" .= auditDetail.trace
      , "reason" .= auditDetail.reason
      ]

-- | Paginated list of audit log summaries.
data AuditListResponse = AuditListResponse
  { items :: [AuditSummaryResponse]
  , nextCursor :: Maybe Text
  }

instance ToJSON AuditListResponse where
  toJSON listResponse =
    object
      [ "items" .= listResponse.items
      , "nextCursor" .= listResponse.nextCursor
      ]

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

{- | @GET \/audit@ handler.

Requires @audit:read@ permission.  MVP: trace and eventType filters are
accepted but not applied (returns all audit logs up to limit).
-}
getAuditLogsHandler ::
  AppEnv ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  Maybe Int ->
  Maybe Text ->
  Handler AuditListResponse
getAuditLogsHandler
  appEnvironment
  maybeAuthHeader
  _maybeTrace
  _maybeEventType
  _maybeFrom
  _maybeTo
  maybeLimit
  _maybeCursor = do
    _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "audit:read"

    let auditQueryFilter =
          AuditQueryFilter
            { traceFilter = Nothing
            , eventTypeFilter = Nothing
            , limitCount = maybe 50 (min 200 . max 1) maybeLimit
            }

    auditResult <-
      liftIO $
        listAuditLogs
          FirestoreAuditRepositoryEnv
            { firestoreContext = appEnvironment.firestoreContext
            }
          auditQueryFilter

    auditSummaries <- case auditResult of
      Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
      Right items -> pure items

    pure
      AuditListResponse
        { items = map toAuditSummaryResponse auditSummaries
        , nextCursor = Nothing
        }

{- | @GET \/audit\/{identifier}@ handler.

Requires @audit:read@ permission.  Returns 404 when the log entry does not exist.
-}
getAuditLogByIdentifierHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  Handler AuditDetailResponse
getAuditLogByIdentifierHandler appEnvironment auditIdentifier maybeAuthHeader = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "audit:read"

  detailResult <-
    liftIO $
      getAuditLogByIdentifier
        FirestoreAuditRepositoryEnv
          { firestoreContext = appEnvironment.firestoreContext
          }
        auditIdentifier

  maybeDetail <- case detailResult of
    Left firestoreError -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right maybeValue -> pure maybeValue

  case maybeDetail of
    Nothing ->
      throwError
        err404
          { errBody = encode (problemJson "Not Found" 404 "Audit log not found" "RESOURCE_NOT_FOUND")
          , errHeaders = [(hContentType, "application/problem+json")]
          , errReasonPhrase = "Not Found"
          }
    Just auditDetail -> pure (toAuditDetailResponse auditDetail)

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

toAuditSummaryResponse :: AuditSummary -> AuditSummaryResponse
toAuditSummaryResponse auditSummary =
  AuditSummaryResponse
    { identifier = auditSummary.identifier
    , occurredAt = Text.pack (show auditSummary.occurredAt)
    , eventType = auditSummary.eventType
    , service = auditSummary.service
    , result = auditResultToText auditSummary.result
    , trace = auditSummary.trace
    }

toAuditDetailResponse :: AuditDetail -> AuditDetailResponse
toAuditDetailResponse auditDetail =
  AuditDetailResponse
    { identifier = auditDetail.identifier
    , occurredAt = Text.pack (show auditDetail.occurredAt)
    , eventType = auditDetail.eventType
    , service = auditDetail.service
    , result = auditResultToText auditDetail.result
    , trace = auditDetail.trace
    , reason = auditDetail.reason
    }
