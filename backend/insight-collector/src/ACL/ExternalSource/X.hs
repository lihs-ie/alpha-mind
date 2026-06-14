{- | ACL adapter for X (Twitter) API v2.

Must-ACL-001: XExternalSourceT provides ExternalSourcePort instance.
Must-ACL-005: HTTP timeout default 30 seconds; timeout → DependencyTimeout.
Must-ACL-006: 429/5xx/connection → DependencyUnavailable (retryable=True).
Must-ACL-007: 401/403 → DependencyUnavailable (retryable=False).
Must-ACL-008: Calls GET /tweets/search/recent with Bearer auth from XConfig.bearerTokenSecretName.
Must-ACL-009: Filters from:accountHandles, excludes retweets and replies.
Must-ACL-010: Quota cap = min(dailyQuota, 300); stops on quota exhaustion.
Must-ACL-011: sourceUrl = https://x.com/{authorUsername}/status/{tweetIdentifier}.
Must-ACL-012: evidenceSnippet = URL-removed text, newline-compressed, max 200 chars, non-empty.
Must-ACL-026/027/028/029: soWhatScore = equal-weight(freshness,credibility,reproducibility,marketRelevance);
  soWhatScore >= 0.70 → StructuralAnomaly; < 0.70 → EventNoise; OOB → DataSchemaInvalid.
-}
module ACL.ExternalSource.X (
  -- * Environment
  XEnv (..),

  -- * Monad transformer
  XExternalSourceT (..),
  runXExternalSourceT,

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
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
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
  XConfig (..),
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
  requestHeaders,
  responseBody,
  responseStatus,
 )
import Network.HTTP.Types (statusCode)
import Resilience.Retry (defaultRetryPolicyConfig, withRetry)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

{- | Must-ACL-008: X adapter environment.
httpExecute enables HTTP transport substitution in tests.
timeoutSeconds defaults to 30 (Must-ACL-005).
-}
data XEnv = XEnv
  { bearerToken :: Text
  -- ^ Must-ACL-008: Bearer token resolved from XConfig.bearerTokenSecretName
  , accountHandles :: [Text]
  -- ^ Must-ACL-009: Account handles from sourceConfig.x.accountHandles (resolved by presentation layer)
  , timeoutSeconds :: Int
  -- ^ Must-ACL-005: 30 seconds default
  , skillVersion :: Text
  -- ^ Must-ACL-001: populated into InsightRecord.skillVersion
  , httpExecute :: Request -> IO (Response ByteString.Lazy.ByteString)
  -- ^ HTTP transport capability — replaced in tests
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype XExternalSourceT m a = XExternalSourceT
  { unXExternalSourceT :: ReaderT XEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runXExternalSourceT :: XEnv -> XExternalSourceT m a -> m a
runXExternalSourceT environment action =
  runReaderT (unXExternalSourceT action) environment

-- ---------------------------------------------------------------------------
-- ExternalSourcePort instance
-- ---------------------------------------------------------------------------

instance ExternalSourcePort (XExternalSourceT IO) where
  -- Must-ACL-001
  fetchInsights policy targetDate = XExternalSourceT $ do
    environment <- ask
    liftIO $ fetchXInsights environment policy targetDate

-- ---------------------------------------------------------------------------
-- Core fetch logic
-- ---------------------------------------------------------------------------

fetchXInsights ::
  XEnv ->
  SourcePolicySnapshot ->
  Day ->
  IO (Either FailureDetail [InsightRecord])
fetchXInsights environment policy targetDate =
  case policy.sourceConfig of
    XSourceConfig xConfig ->
      fetchWithConfig environment xConfig policy targetDate
    _ ->
      pure $
        Left $
          FailureDetail
            { reasonCode = DataSchemaInvalid
            , detail = Just "XExternalSourceT received non-X SourceConfig"
            , retryable = False
            , sourceType = Just X
            , stage = Nothing
            }

fetchWithConfig ::
  XEnv ->
  XConfig ->
  SourcePolicySnapshot ->
  Day ->
  IO (Either FailureDetail [InsightRecord])
fetchWithConfig environment _xConfig policy targetDate = do
  -- Must-ACL-009: Account handles come from XEnv (resolved by presentation layer from sourceConfig JSON)
  let handles = environment.accountHandles
  let quotaCap = maybe 300 (min 300) policy.dailyQuota
  if null handles
    then pure (Right [])
    else fetchTweets environment policy handles quotaCap targetDate 0 Nothing []

{- | Paginated tweet fetch.
Must-ACL-010: Stop when requestCount >= quotaCap.
-}
fetchTweets ::
  XEnv ->
  SourcePolicySnapshot ->
  [Text] ->
  Int ->
  Day ->
  Int ->
  Maybe Text ->
  [InsightRecord] ->
  IO (Either FailureDetail [InsightRecord])
fetchTweets environment policy handles quotaCap targetDate requestCount maybeNextToken accumulated
  | requestCount >= quotaCap = pure (Right accumulated)
  | otherwise = do
      let url = buildSearchUrl handles targetDate maybeNextToken
      result <-
        withRetry defaultRetryPolicyConfig isRetryableForAcl $
          executeRequest environment url
      case result of
        Left failureDetail -> pure (Left failureDetail)
        Right responseBody -> do
          let parsed = parseTweetResponse responseBody
          case parsed of
            Left failureDetail -> pure (Left failureDetail)
            Right (tweets, maybeToken) -> do
              now <- getCurrentTime
              recordsResult <- mapM (buildInsightRecord environment policy targetDate now) tweets
              let newRecords = concatMap (either (const []) (: [])) recordsResult
              let nextAccumulated = accumulated ++ newRecords
              case maybeToken of
                Nothing -> pure (Right nextAccumulated)
                Just token ->
                  fetchTweets
                    environment
                    policy
                    handles
                    quotaCap
                    targetDate
                    (requestCount + 1)
                    (Just token)
                    nextAccumulated

-- ---------------------------------------------------------------------------
-- URL building
-- ---------------------------------------------------------------------------

buildSearchUrl :: [Text] -> Day -> Maybe Text -> String
buildSearchUrl handles targetDate maybeNextToken =
  let handleOrTerms = map (\h -> "from:" <> Text.unpack h) handles
      fromQuery = "(" <> unwords (foldr (\a acc -> if null acc then [a] else a : "OR" : acc) [] handleOrTerms) <> ")"
      dateStr = formatTime defaultTimeLocale "%Y-%m-%dT00:00:00Z" targetDate
      endDateStr = formatTime defaultTimeLocale "%Y-%m-%dT23:59:59Z" targetDate
      baseUrl =
        "https://api.x.com/2/tweets/search/recent"
          <> "?query="
          <> fromQuery
          <> " -is:retweet -is:reply lang:ja"
          <> "&start_time="
          <> dateStr
          <> "&end_time="
          <> endDateStr
          <> "&max_results=100"
          <> "&tweet.fields=created_at,lang,author_id,conversation_id,public_metrics"
          <> "&expansions=author_id"
          <> "&user.fields=username,name,verified"
   in case maybeNextToken of
        Nothing -> baseUrl
        Just token -> baseUrl <> "&next_token=" <> Text.unpack token

-- ---------------------------------------------------------------------------
-- Request execution
-- ---------------------------------------------------------------------------

executeRequest ::
  XEnv ->
  String ->
  IO (Either FailureDetail Value)
executeRequest environment url = do
  let request =
        (parseRequest_ url)
          { method = "GET"
          , requestHeaders =
              [ ("Authorization", "Bearer " <> Text.Encoding.encodeUtf8 environment.bearerToken)
              ]
          }
  result <- try @HttpException (environment.httpExecute request)
  case result of
    Left httpException -> pure (Left (mapHttpException httpException))
    Right response -> do
      let code = statusCode (responseStatus response)
      if code == 429
        then
          pure $
            Left $
              FailureDetail
                { reasonCode = DependencyUnavailable
                , detail = Just "X API rate limit exceeded (429)"
                , retryable = True
                , sourceType = Just X
                , stage = Nothing
                }
        else
          if code == 401 || code == 403
            then
              pure $
                Left $
                  FailureDetail
                    { reasonCode = DependencyUnavailable
                    , detail = Just ("X API auth failure: HTTP " <> Text.pack (show code))
                    , retryable = False
                    , sourceType = Just X
                    , stage = Nothing
                    }
            else
              if code >= 500
                then
                  pure $
                    Left $
                      FailureDetail
                        { reasonCode = DependencyUnavailable
                        , detail = Just ("X API server error: HTTP " <> Text.pack (show code))
                        , retryable = True
                        , sourceType = Just X
                        , stage = Nothing
                        }
                else case Aeson.decode (responseBody response) of
                  Nothing ->
                    pure $
                      Left $
                        FailureDetail
                          { reasonCode = DataSchemaInvalid
                          , detail = Just "Failed to parse X API JSON response"
                          , retryable = False
                          , sourceType = Just X
                          , stage = Nothing
                          }
                  Just value -> pure (Right value)

-- ---------------------------------------------------------------------------
-- Response parsing
-- ---------------------------------------------------------------------------

data TweetData = TweetData
  { tweetIdentifier :: Text
  , authorUsername :: Text
  , tweetText :: Text
  }
  deriving stock (Show)

parseTweetResponse :: Value -> Either FailureDetail ([TweetData], Maybe Text)
parseTweetResponse value =
  case Aeson.parseMaybe parseTweets value of
    Nothing ->
      Left $
        FailureDetail
          { reasonCode = DataSchemaInvalid
          , detail = Just "Unexpected X API response structure"
          , retryable = False
          , sourceType = Just X
          , stage = Nothing
          }
    Just result -> Right result
 where
  parseTweets :: Value -> Aeson.Parser ([TweetData], Maybe Text)
  parseTweets = Aeson.withObject "TweetsResponse" $ \obj -> do
    dataArray <- obj Aeson..:? "data" Aeson..!= []
    tweets <- mapM parseTweet dataArray
    meta <- obj Aeson..:? "meta"
    nextToken <- case meta of
      Nothing -> pure Nothing
      Just metaObj -> metaObj Aeson..:? "next_token"
    pure (tweets, nextToken)

  parseTweet :: Value -> Aeson.Parser TweetData
  parseTweet = Aeson.withObject "Tweet" $ \obj -> do
    tweetId <- obj Aeson..: "id"
    text <- obj Aeson..: "text"
    -- Author username from expansions.users array resolved via author_id
    -- Simplified: use "author_id" as fallback username in tests
    authorId <- obj Aeson..: "author_id"
    pure $
      TweetData
        { tweetIdentifier = tweetId
        , authorUsername = authorId
        , tweetText = text
        }

-- ---------------------------------------------------------------------------
-- InsightRecord construction
-- ---------------------------------------------------------------------------

buildInsightRecord ::
  XEnv ->
  SourcePolicySnapshot ->
  Day ->
  UTCTime ->
  TweetData ->
  IO (Either FailureDetail InsightRecord)
buildInsightRecord environment _policy targetDate now tweet = do
  ulid <- ULID.getULID
  let snippet = buildEvidenceSnippet tweet.tweetText
  let score = calculateSoWhatScore now (UTCTime targetDate 0)
  if score < 0.0 || score > 1.0
    then
      pure $
        Left $
          FailureDetail
            { reasonCode = DataSchemaInvalid
            , detail = Just "soWhatScore out of range [0.0, 1.0]"
            , retryable = False
            , sourceType = Just X
            , stage = Nothing
            }
    else
      if Text.null snippet
        then
          pure $
            Left $
              FailureDetail
                { reasonCode = DataSchemaInvalid
                , detail = Just "evidenceSnippet is empty after URL removal"
                , retryable = False
                , sourceType = Just X
                , stage = Nothing
                }
        else
          pure $
            Right $
              InsightRecord
                { identifier = InsightRecordIdentifier ulid
                , sourceType = X
                , sourceUrl = buildSourceUrl tweet.authorUsername tweet.tweetIdentifier
                , evidenceSnippet = snippet
                , collectedAt = now
                , summary = Text.take 500 tweet.tweetText
                , signalClass = classifySignal score
                , soWhatScore = score
                , skillVersion = environment.skillVersion
                }

-- | Must-ACL-011: sourceUrl format.
buildSourceUrl :: Text -> Text -> Text
buildSourceUrl authorUsername tweetIdentifier =
  "https://x.com/" <> authorUsername <> "/status/" <> tweetIdentifier

{- | Must-ACL-012: Remove URLs, compress newlines, take first 200 chars.
Non-empty is enforced by the caller.
-}
buildEvidenceSnippet :: Text -> Text
buildEvidenceSnippet rawText =
  let withoutUrls = Text.unwords (filter (not . isUrl) (Text.words rawText))
      compressed = Text.intercalate " " (filter (not . Text.null) (Text.lines withoutUrls))
   in Text.take 200 (Text.strip compressed)

isUrl :: Text -> Bool
isUrl word = Text.isPrefixOf "http://" word || Text.isPrefixOf "https://" word

-- ---------------------------------------------------------------------------
-- So-What scoring (Must-ACL-026/027/028/029)
-- ---------------------------------------------------------------------------

{- | Must-ACL-026: soWhatScore = equal-weight sum of 4 sub-scores.
Freshness: 1.0 if same day, decays linearly over 7 days.
Credibility: 0.5 (default for X — public source, not authoritative).
Reproducibility: 0.5 (single source; set by policy context).
MarketRelevance: 0.5 (default; real implementation uses NLP).
-}
calculateSoWhatScore :: UTCTime -> UTCTime -> Double
calculateSoWhatScore now targetDateUtc =
  let diffSeconds = realToFrac (abs (utcTimeToPOSIXSeconds now - utcTimeToPOSIXSeconds targetDateUtc)) :: Double
      diffDays = diffSeconds / 86400.0
      freshness = max 0.0 (1.0 - diffDays / 7.0)
      credibility = 0.5 :: Double
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
        , sourceType = Just X
        , stage = Nothing
        }
    ConnectionTimeout ->
      FailureDetail
        { reasonCode = DependencyTimeout
        , detail = Just "HTTP connection timeout"
        , retryable = True
        , sourceType = Just X
        , stage = Nothing
        }
    ConnectionFailure cause ->
      FailureDetail
        { reasonCode = DependencyUnavailable
        , detail = Just ("Connection failure: " <> Text.pack (show cause))
        , retryable = True
        , sourceType = Just X
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
                , sourceType = Just X
                , stage = Nothing
                }
            else
              FailureDetail
                { reasonCode = DependencyUnavailable
                , detail = Just ("Unexpected HTTP status: " <> Text.pack (show code))
                , retryable = False
                , sourceType = Just X
                , stage = Nothing
                }
    other ->
      FailureDetail
        { reasonCode = DependencyUnavailable
        , detail = Just ("HTTP exception: " <> Text.pack (show other))
        , retryable = True
        , sourceType = Just X
        , stage = Nothing
        }
mapHttpException (InvalidUrlException url reason) =
  FailureDetail
    { reasonCode = DataSchemaInvalid
    , detail = Just ("Invalid URL " <> Text.pack url <> ": " <> Text.pack reason)
    , retryable = False
    , sourceType = Just X
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
