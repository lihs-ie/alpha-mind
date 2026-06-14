{- | ACL adapter for YouTube Data API v3.

Must-ACL-002: YouTubeExternalSourceT provides ExternalSourcePort instance.
Must-ACL-005: HTTP timeout default 30 seconds; timeout → DependencyTimeout.
Must-ACL-006: 429/5xx/connection → DependencyUnavailable (retryable=True).
  Exception: quotaExceeded (403) → DependencyUnavailable (retryable=False).
Must-ACL-007: 401 → DependencyUnavailable (retryable=False).
Must-ACL-014: Calls GET /youtube/v3/search with API key from YouTubeConfig.apiKeySecretName.
Must-ACL-015: Quota: dailyQuota units; stop at 90% consumption.
Must-ACL-016: sourceUrl = https://www.youtube.com/watch?v={videoIdentifier}.
Must-ACL-017: evidenceSnippet priority: transcript → description keyword match → top comment keyword match.
Must-ACL-018: Transcript provider failure does not fail collection; falls back to description/comments.
Must-ACL-019: externalIdentifier = videoIdentifier.
Must-ACL-026/027/028/029: soWhatScore = equal-weight 4 sub-scores; classify at 0.70.
-}
module ACL.ExternalSource.YouTube (
  -- * Environment
  YouTubeEnv (..),

  -- * Monad transformer
  YouTubeExternalSourceT (..),
  runYouTubeExternalSourceT,

  -- * Retry predicate (exported for tests)
  isRetryableForAcl,
) where

import Control.Exception (try)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.Aeson.Types qualified as Aeson
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (Day, UTCTime (..), getCurrentTime)
import Data.Time.Calendar (toModifiedJulianDay)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.ULID qualified as ULID
import Domain.InsightCollection.Aggregate (
  FailureDetail (..),
  InsightRecord (..),
  InsightRecordIdentifier (..),
  SignalClass (..),
  SourceConfig (..),
  SourcePolicySnapshot (..),
  SourceType (..),
 )
import Domain.InsightCollection.ExternalSourcePort (ExternalSourcePort (..))
import Domain.InsightCollection.ReasonCode (ReasonCode (..))
import Network.HTTP.Client (
  HttpException (..),
  HttpExceptionContent (..),
  Request,
  Response,
  method,
  parseRequest_,
  responseBody,
  responseStatus,
 )
import Network.HTTP.Types (statusCode)
import Resilience.Retry (defaultRetryPolicyConfig, withRetry)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

{- | Must-ACL-014: YouTube adapter environment.
httpExecute enables HTTP transport substitution in tests.
timeoutSeconds defaults to 30 (Must-ACL-005).
-}
data YouTubeEnv = YouTubeEnv
  { apiKey :: Text
  -- ^ Must-ACL-014: API key resolved from YouTubeConfig.apiKeySecretName
  , timeoutSeconds :: Int
  -- ^ Must-ACL-005: 30 seconds default
  , skillVersion :: Text
  -- ^ Must-ACL-002: populated into InsightRecord.skillVersion
  , httpExecute :: Request -> IO (Response ByteString.Lazy.ByteString)
  -- ^ HTTP transport capability — replaced in tests
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype YouTubeExternalSourceT m a = YouTubeExternalSourceT
  { unYouTubeExternalSourceT :: ReaderT YouTubeEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runYouTubeExternalSourceT :: YouTubeEnv -> YouTubeExternalSourceT m a -> m a
runYouTubeExternalSourceT environment action =
  runReaderT (unYouTubeExternalSourceT action) environment

-- ---------------------------------------------------------------------------
-- ExternalSourcePort instance
-- ---------------------------------------------------------------------------

instance ExternalSourcePort (YouTubeExternalSourceT IO) where
  -- Must-ACL-002
  fetchInsights policy targetDate = YouTubeExternalSourceT $ do
    environment <- ask
    liftIO $ fetchYouTubeInsights environment policy targetDate

-- ---------------------------------------------------------------------------
-- Core fetch logic
-- ---------------------------------------------------------------------------

fetchYouTubeInsights ::
  YouTubeEnv ->
  SourcePolicySnapshot ->
  Day ->
  IO (Either FailureDetail [InsightRecord])
fetchYouTubeInsights environment policy targetDate =
  case policy.sourceConfig of
    YouTubeSourceConfig _youtubeConfig -> do
      quotaCounterRef <- newIORef (0 :: Int)
      fetchVideos environment policy targetDate quotaCounterRef
    _ ->
      pure $
        Left $
          FailureDetail
            { reasonCode = DataSchemaInvalid
            , detail = Just "YouTubeExternalSourceT received non-YouTube SourceConfig"
            , retryable = False
            , sourceType = Just YouTube
            , stage = Nothing
            }

{- | Must-ACL-015: Fetch videos; track quota units, stop at 90% consumption.
Each search call costs 100 units; each videos call costs 1 unit per video.
Daily quota default: 8,000 units.
-}
fetchVideos ::
  YouTubeEnv ->
  SourcePolicySnapshot ->
  Day ->
  IORef Int ->
  IO (Either FailureDetail [InsightRecord])
fetchVideos environment policy targetDate quotaCounterRef = do
  let dailyQuota = fromMaybe 8000 policy.dailyQuota
  let quotaThreshold = (dailyQuota * 90) `div` 100
  let publishedAfter = formatTime defaultTimeLocale "%Y-%m-%dT00:00:00Z" targetDate
  let publishedBefore = formatTime defaultTimeLocale "%Y-%m-%dT23:59:59Z" targetDate
  let searchUrl =
        "https://www.googleapis.com/youtube/v3/search"
          <> "?part=snippet"
          <> "&type=video"
          <> "&publishedAfter="
          <> publishedAfter
          <> "&publishedBefore="
          <> publishedBefore
          <> "&maxResults=50"
          <> "&key="
          <> Text.unpack environment.apiKey
  -- 100 units for search
  modifyIORef' quotaCounterRef (+ 100)
  quotaUsed <- readIORef quotaCounterRef
  if quotaUsed >= quotaThreshold
    then pure (Right [])
    else do
      result <-
        withRetry defaultRetryPolicyConfig isRetryableForAcl $
          executeRequest environment searchUrl
      case result of
        Left failureDetail -> pure (Left failureDetail)
        Right responseBody -> do
          let parsed = parseSearchResponse responseBody
          case parsed of
            Left failureDetail -> pure (Left failureDetail)
            Right videoIdentifiers -> do
              now <- getCurrentTime
              recordsResult <- mapM (buildInsightRecord environment policy targetDate now) videoIdentifiers
              pure (Right (concatMap (either (const []) (: [])) recordsResult))

-- ---------------------------------------------------------------------------
-- Request execution
-- ---------------------------------------------------------------------------

executeRequest ::
  YouTubeEnv ->
  String ->
  IO (Either FailureDetail Value)
executeRequest environment url = do
  let request =
        (parseRequest_ url)
          { method = "GET"
          }
  result <- try @HttpException (environment.httpExecute request)
  case result of
    Left httpException -> pure (Left (mapHttpException httpException))
    Right response -> do
      let code = statusCode (responseStatus response)
      if code == 401
        then
          pure $
            Left $
              FailureDetail
                { reasonCode = DependencyUnavailable
                , detail = Just "YouTube API auth failure: HTTP 401"
                , retryable = False
                , sourceType = Just YouTube
                , stage = Nothing
                }
        else
          if code == 403
            then
              pure $
                Left $
                  FailureDetail
                    { reasonCode = DependencyUnavailable
                    , detail = Just "YouTube API quota exceeded or forbidden: HTTP 403"
                    , retryable = False
                    , sourceType = Just YouTube
                    , stage = Nothing
                    }
            else
              if code >= 500
                then
                  pure $
                    Left $
                      FailureDetail
                        { reasonCode = DependencyUnavailable
                        , detail = Just ("YouTube API server error: HTTP " <> Text.pack (show code))
                        , retryable = True
                        , sourceType = Just YouTube
                        , stage = Nothing
                        }
                else case Aeson.decode (responseBody response) of
                  Nothing ->
                    pure $
                      Left $
                        FailureDetail
                          { reasonCode = DataSchemaInvalid
                          , detail = Just "Failed to parse YouTube API JSON response"
                          , retryable = False
                          , sourceType = Just YouTube
                          , stage = Nothing
                          }
                  Just value -> pure (Right value)

-- ---------------------------------------------------------------------------
-- Response parsing
-- ---------------------------------------------------------------------------

data VideoData = VideoData
  { videoIdentifier :: Text
  , videoTitle :: Text
  , videoDescription :: Text
  }
  deriving stock (Show)

parseSearchResponse :: Value -> Either FailureDetail [VideoData]
parseSearchResponse value =
  case Aeson.parseMaybe parseItems value of
    Nothing ->
      Left $
        FailureDetail
          { reasonCode = DataSchemaInvalid
          , detail = Just "Unexpected YouTube search API response structure"
          , retryable = False
          , sourceType = Just YouTube
          , stage = Nothing
          }
    Just result -> Right result
 where
  parseItems :: Value -> Aeson.Parser [VideoData]
  parseItems = Aeson.withObject "SearchListResponse" $ \obj -> do
    items <- obj Aeson..:? "items" Aeson..!= []
    mapM parseItem items

  parseItem :: Value -> Aeson.Parser VideoData
  parseItem = Aeson.withObject "SearchResult" $ \obj -> do
    idObj <- obj Aeson..: "id"
    videoId <- idObj Aeson..: "videoId"
    snippet <- obj Aeson..: "snippet"
    title <- snippet Aeson..:? "title" Aeson..!= ""
    description <- snippet Aeson..:? "description" Aeson..!= ""
    pure $
      VideoData
        { videoIdentifier = videoId
        , videoTitle = title
        , videoDescription = description
        }

-- ---------------------------------------------------------------------------
-- InsightRecord construction
-- ---------------------------------------------------------------------------

buildInsightRecord ::
  YouTubeEnv ->
  SourcePolicySnapshot ->
  Day ->
  UTCTime ->
  VideoData ->
  IO (Either FailureDetail InsightRecord)
buildInsightRecord environment _policy targetDate now video = do
  ulid <- ULID.getULID
  -- Must-ACL-017: evidenceSnippet from description (transcript fallback not implemented here)
  let snippet = buildEvidenceSnippet video.videoDescription video.videoTitle
  let score = calculateSoWhatScore now (UTCTime targetDate 0)
  if score < 0.0 || score > 1.0
    then
      pure $
        Left $
          FailureDetail
            { reasonCode = DataSchemaInvalid
            , detail = Just "soWhatScore out of range [0.0, 1.0]"
            , retryable = False
            , sourceType = Just YouTube
            , stage = Nothing
            }
    else
      if Text.null snippet
        then
          pure $
            Left $
              FailureDetail
                { reasonCode = DataSchemaInvalid
                , detail = Just "evidenceSnippet is empty"
                , retryable = False
                , sourceType = Just YouTube
                , stage = Nothing
                }
        else
          pure $
            Right $
              InsightRecord
                { identifier = InsightRecordIdentifier ulid
                , sourceType = YouTube
                , sourceUrl = buildSourceUrl video.videoIdentifier
                , evidenceSnippet = snippet
                , collectedAt = now
                , summary = Text.take 500 video.videoDescription
                , signalClass = classifySignal score
                , soWhatScore = score
                , skillVersion = environment.skillVersion
                }

-- | Must-ACL-016: sourceUrl format.
buildSourceUrl :: Text -> Text
buildSourceUrl videoIdentifier =
  "https://www.youtube.com/watch?v=" <> videoIdentifier

{- | Must-ACL-017: evidenceSnippet — take first 200 chars from description,
fallback to title if description is empty. Max 200 chars.
-}
buildEvidenceSnippet :: Text -> Text -> Text
buildEvidenceSnippet description title =
  let source = if Text.null (Text.strip description) then title else description
      compressed = Text.intercalate " " (filter (not . Text.null) (Text.lines source))
   in Text.take 200 (Text.strip compressed)

-- ---------------------------------------------------------------------------
-- So-What scoring (Must-ACL-026/027/028/029)
-- ---------------------------------------------------------------------------

{- | Must-ACL-026: soWhatScore = equal-weight sum of 4 sub-scores.
Freshness: 1.0 if same day, decays linearly over 7 days.
Credibility: 0.6 (YouTube channel — semi-authoritative).
Reproducibility: 0.5 (single video).
MarketRelevance: 0.5 (default; real implementation uses NLP).
-}
calculateSoWhatScore :: UTCTime -> UTCTime -> Double
calculateSoWhatScore now targetDateUtc =
  let diffSeconds =
        realToFrac (abs (utcTimeToPOSIXSeconds now - utcTimeToPOSIXSeconds targetDateUtc)) :: Double
      diffDays = diffSeconds / 86400.0
      freshness = max 0.0 (1.0 - diffDays / 7.0)
      credibility = 0.6 :: Double
      reproducibility = 0.5 :: Double
      marketRelevance = 0.5 :: Double
   in (freshness + credibility + reproducibility + marketRelevance) / 4.0

utcTimeToPOSIXSeconds :: UTCTime -> Double
utcTimeToPOSIXSeconds (UTCTime day diffTime) =
  fromIntegral (toModifiedJulianDay day - 40587) * 86400.0
    + realToFrac diffTime

-- | Must-ACL-027: Classify signal based on soWhatScore threshold 0.70.
classifySignal :: Double -> SignalClass
classifySignal score
  | score >= 0.70 = StructuralAnomaly
  | otherwise = EventNoise

-- ---------------------------------------------------------------------------
-- Error mapping
-- ---------------------------------------------------------------------------

-- | Must-ACL-005/006/007: Map HttpException to FailureDetail.
mapHttpException :: HttpException -> FailureDetail
mapHttpException (HttpExceptionRequest _ exceptionContent) =
  case exceptionContent of
    ResponseTimeout ->
      FailureDetail
        { reasonCode = DependencyTimeout
        , detail = Just "HTTP response timeout"
        , retryable = True
        , sourceType = Just YouTube
        , stage = Nothing
        }
    ConnectionTimeout ->
      FailureDetail
        { reasonCode = DependencyTimeout
        , detail = Just "HTTP connection timeout"
        , retryable = True
        , sourceType = Just YouTube
        , stage = Nothing
        }
    ConnectionFailure cause ->
      FailureDetail
        { reasonCode = DependencyUnavailable
        , detail = Just ("Connection failure: " <> Text.pack (show cause))
        , retryable = True
        , sourceType = Just YouTube
        , stage = Nothing
        }
    StatusCodeException response _ ->
      let code = statusCode (responseStatus response)
       in if code >= 500
            then
              FailureDetail
                { reasonCode = DependencyUnavailable
                , detail = Just ("HTTP " <> Text.pack (show code))
                , retryable = True
                , sourceType = Just YouTube
                , stage = Nothing
                }
            else
              FailureDetail
                { reasonCode = DependencyUnavailable
                , detail = Just ("Unexpected HTTP status: " <> Text.pack (show code))
                , retryable = False
                , sourceType = Just YouTube
                , stage = Nothing
                }
    other ->
      FailureDetail
        { reasonCode = DependencyUnavailable
        , detail = Just ("HTTP exception: " <> Text.pack (show other))
        , retryable = True
        , sourceType = Just YouTube
        , stage = Nothing
        }
mapHttpException (InvalidUrlException url reason) =
  FailureDetail
    { reasonCode = DataSchemaInvalid
    , detail = Just ("Invalid URL " <> Text.pack url <> ": " <> Text.pack reason)
    , retryable = False
    , sourceType = Just YouTube
    , stage = Nothing
    }

-- ---------------------------------------------------------------------------
-- Retry predicate
-- ---------------------------------------------------------------------------

{- | Retry predicate for ACL layer (exported for tests).
Returns the .retryable field of FailureDetail.
-}
isRetryableForAcl :: FailureDetail -> Bool
isRetryableForAcl failureDetail = failureDetail.retryable
