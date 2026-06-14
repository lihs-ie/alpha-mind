module Presentation.Handler.Insights (
  InsightSummaryResponse (..),
  InsightDetailResponse (..),
  InsightListResponse (..),
  InsightActionResult (..),
  InsightHypothesizeAccepted (..),
  InsightDecisionRequest (..),
  HypothesizeRequest (..),
  getInsightsHandler,
  getInsightByIdentifierHandler,
  adoptInsightHandler,
  rejectInsightHandler,
  hypothesizeInsightHandler,
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
import Domain.Insight.Action (InsightActionError (..), checkMnpiFilter)
import Domain.Insight.Record (
  InsightDetail (..),
  InsightSummary (..),
  insightSentimentToText,
  insightSignalClassToText,
  insightSourceTypeToText,
 )
import Infrastructure.JWT.JwtVerifier (JwtVerifierEnv (..), VerifiedClaims (..), verifyToken)
import Infrastructure.Publisher.PubSubInsightsPublisher (
  PubSubInsightsPublisherEnv (..),
  publishHypothesisProposed,
 )
import Infrastructure.Repository.FirestoreInsightRepository (
  FirestoreInsightRepositoryEnv (..),
  InsightQueryFilter (..),
  InsightStatusUpdate (..),
  getInsightRecordByIdentifier,
  listInsightRecords,
  updateInsightStatus,
 )
import Network.HTTP.Types (hContentType)
import Persistence.Firestore (FirestoreError (..))
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err400, err401, err403, err404, err422, err503, throwError)

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

-- | Request body for insight action endpoints (adopt, reject).
data InsightDecisionRequest = InsightDecisionRequest
  { actionReasonCode :: Text
  , comment :: Maybe Text
  }

instance FromJSON InsightDecisionRequest where
  parseJSON =
    withObject "InsightDecisionRequest" $ \requestObject ->
      InsightDecisionRequest
        <$> requestObject .: "actionReasonCode"
        <*> requestObject .:? "comment"

-- | Optional request body for the hypothesize action.
data HypothesizeRequest = HypothesizeRequest
  { actionReasonCode :: Maybe Text
  , comment :: Maybe Text
  }

instance FromJSON HypothesizeRequest where
  parseJSON =
    withObject "HypothesizeRequest" $ \requestObject ->
      HypothesizeRequest
        <$> requestObject .:? "actionReasonCode"
        <*> requestObject .:? "comment"

-- | Response body for adopt and reject actions (200 OK).
data InsightActionResult = InsightActionResult
  { success :: Bool
  , trace :: Text
  }

instance ToJSON InsightActionResult where
  toJSON actionResult =
    object
      [ "success" .= actionResult.success
      , "trace" .= actionResult.trace
      ]

-- | Response body for hypothesize action (202 Accepted).
data InsightHypothesizeAccepted = InsightHypothesizeAccepted
  { accepted :: Bool
  , identifier :: Text
  , trace :: Text
  }

instance ToJSON InsightHypothesizeAccepted where
  toJSON hypothesizeAccepted =
    object
      [ "accepted" .= hypothesizeAccepted.accepted
      , "identifier" .= hypothesizeAccepted.identifier
      , "trace" .= hypothesizeAccepted.trace
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

{- | @POST \/insights\/{identifier}\/adopt@ handler.

Requires @insights:write@ permission.  Checks for MNPI-suspected keywords
in the comment field, fetches the insight to confirm it exists, updates the
@actionStatus@ field in Firestore to @\"adopted\"@, and returns 200 OK.
-}
adoptInsightHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  InsightDecisionRequest ->
  Handler InsightActionResult
adoptInsightHandler appEnvironment insightIdentifier maybeAuthHeader decisionRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "insights:write"

  checkMnpiComment decisionRequest.comment

  _insightDetail <- fetchInsightOrNotFound appEnvironment insightIdentifier

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID

  let statusUpdate =
        InsightStatusUpdate
          { actionStatus = "adopted"
          , updatedAt = now
          }

  updateResult <-
    liftIO
      ( try
          ( updateInsightStatus
              FirestoreInsightRepositoryEnv
                { firestoreContext = appEnvironment.firestoreContext
                }
              insightIdentifier
              statusUpdate
          ) ::
          IO (Either SomeException (Either FirestoreError ()))
      )

  case updateResult of
    Left _exception -> throwServiceUnavailable "Failed to update insight record"
    Right (Left firestoreError) -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right (Right ()) -> pure ()

  pure
    InsightActionResult
      { success = True
      , trace = Text.pack (show traceUlid)
      }

{- | @POST \/insights\/{identifier}\/reject@ handler.

Requires @insights:write@ permission.  Checks for MNPI-suspected keywords
in the comment field, fetches the insight to confirm it exists, updates the
@actionStatus@ field in Firestore to @\"rejected\"@, and returns 200 OK.
-}
rejectInsightHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  InsightDecisionRequest ->
  Handler InsightActionResult
rejectInsightHandler appEnvironment insightIdentifier maybeAuthHeader decisionRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "insights:write"

  checkMnpiComment decisionRequest.comment

  _insightDetail <- fetchInsightOrNotFound appEnvironment insightIdentifier

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID

  let statusUpdate =
        InsightStatusUpdate
          { actionStatus = "rejected"
          , updatedAt = now
          }

  updateResult <-
    liftIO
      ( try
          ( updateInsightStatus
              FirestoreInsightRepositoryEnv
                { firestoreContext = appEnvironment.firestoreContext
                }
              insightIdentifier
              statusUpdate
          ) ::
          IO (Either SomeException (Either FirestoreError ()))
      )

  case updateResult of
    Left _exception -> throwServiceUnavailable "Failed to update insight record"
    Right (Left firestoreError) -> throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right (Right ()) -> pure ()

  pure
    InsightActionResult
      { success = True
      , trace = Text.pack (show traceUlid)
      }

{- | @POST \/insights\/{identifier}\/hypothesize@ handler.

Requires @insights:write@ permission.  Checks for MNPI-suspected keywords
in the optional comment field, fetches the insight to confirm it exists,
publishes a @hypothesis.proposed@ CloudEvent to Pub/Sub, and returns
202 Accepted with the new hypothesis identifier.
-}
hypothesizeInsightHandler ::
  AppEnv ->
  Text ->
  Maybe Text ->
  HypothesizeRequest ->
  Handler InsightHypothesizeAccepted
hypothesizeInsightHandler appEnvironment insightIdentifier maybeAuthHeader hypothesizeRequest = do
  _verifiedClaims <- requireAuth appEnvironment maybeAuthHeader "insights:write"

  checkMnpiComment hypothesizeRequest.comment

  insightDetail <- fetchInsightOrNotFound appEnvironment insightIdentifier

  now <- liftIO getCurrentTime
  traceUlid <- liftIO ULID.getULID
  eventUlid <- liftIO ULID.getULID
  hypothesisUlid <- liftIO ULID.getULID

  let publisherEnvironment =
        PubSubInsightsPublisherEnv
          { publisher = appEnvironment.pubSubPublisher
          , hypothesisProposedTopicName = appEnvironment.hypothesisProposedTopicName
          }

  liftIO $
    publishHypothesisProposed
      publisherEnvironment
      eventUlid
      traceUlid
      hypothesisUlid
      now
      insightIdentifier
      insightDetail.skillVersion

  pure
    InsightHypothesizeAccepted
      { accepted = True
      , identifier = Text.pack (show hypothesisUlid)
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

-- | Check optional comment for MNPI-suspected keywords; throw 422 if detected.
checkMnpiComment :: Maybe Text -> Handler ()
checkMnpiComment Nothing = pure ()
checkMnpiComment (Just commentText) =
  case checkMnpiFilter commentText of
    Left (MnpiSuspected keyword) ->
      throwUnprocessableEntity
        ("MNPI-suspected keyword detected in comment: " <> keyword)
        "COMPLIANCE_MNPI_SUSPECTED"
    Right () -> pure ()

-- | Fetch an insight by identifier, returning 404 if not found or 503 on Firestore error.
fetchInsightOrNotFound :: AppEnv -> Text -> Handler InsightDetail
fetchInsightOrNotFound appEnvironment insightIdentifier = do
  detailResult <-
    liftIO
      ( try
          ( getInsightRecordByIdentifier
              FirestoreInsightRepositoryEnv
                { firestoreContext = appEnvironment.firestoreContext
                }
              insightIdentifier
          ) ::
          IO (Either SomeException (Either FirestoreError (Maybe InsightDetail)))
      )
  case detailResult of
    Left _exception ->
      throwServiceUnavailable "Failed to read insight record"
    Right (Left firestoreError) ->
      throwServiceUnavailable (firestoreErrorToText firestoreError)
    Right (Right Nothing) ->
      throwNotFound "Insight record not found"
    Right (Right (Just insightDetail)) ->
      pure insightDetail

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

throwUnprocessableEntity :: Text -> Text -> Handler a
throwUnprocessableEntity detailText reasonCodeText =
  throwError
    err422
      { errBody = encode (problemJson "Unprocessable Entity" 422 detailText reasonCodeText)
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Unprocessable Entity"
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
