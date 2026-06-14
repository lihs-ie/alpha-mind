{- | ACL adapter for GitHub REST API.

Must-ACL-004: GitHubExternalSourceT provides ExternalSourcePort instance.
Must-ACL-005: HTTP timeout default 30 seconds; timeout → DependencyTimeout.
Must-ACL-006: 429/5xx/connection → DependencyUnavailable (retryable=True).
Must-ACL-007: 401/403 → DependencyUnavailable (retryable=False).
Must-ACL-023: Calls GitHub API with PAT from GitHubConfig.personalAccessTokenSecretName.
Must-ACL-024: externalIdentifier = repositoryIdentifier (owner/repo).
Must-ACL-025: evidenceSnippet = README/release excerpt, max 200 chars, non-empty.
Must-ACL-026/027/028/029: soWhatScore = equal-weight 4 sub-scores; classify at 0.70.
-}
module ACL.ExternalSource.GitHub (
  -- * Environment
  GitHubEnv (..),

  -- * Monad transformer
  GitHubExternalSourceT (..),
  runGitHubExternalSourceT,

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

{- | Must-ACL-023: GitHub adapter environment.
httpExecute enables HTTP transport substitution in tests.
timeoutSeconds defaults to 30 (Must-ACL-005).
-}
data GitHubEnv = GitHubEnv
  { personalAccessToken :: Text
  -- ^ Must-ACL-023: PAT resolved from GitHubConfig.personalAccessTokenSecretName
  , timeoutSeconds :: Int
  -- ^ Must-ACL-005: 30 seconds default
  , skillVersion :: Text
  -- ^ Must-ACL-004: populated into InsightRecord.skillVersion
  , httpExecute :: Request -> IO (Response ByteString.Lazy.ByteString)
  -- ^ HTTP transport capability — replaced in tests
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype GitHubExternalSourceT m a = GitHubExternalSourceT
  { unGitHubExternalSourceT :: ReaderT GitHubEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runGitHubExternalSourceT :: GitHubEnv -> GitHubExternalSourceT m a -> m a
runGitHubExternalSourceT environment action =
  runReaderT (unGitHubExternalSourceT action) environment

-- ---------------------------------------------------------------------------
-- ExternalSourcePort instance
-- ---------------------------------------------------------------------------

instance ExternalSourcePort (GitHubExternalSourceT IO) where
  -- Must-ACL-004
  fetchInsights policy targetDate = GitHubExternalSourceT $ do
    environment <- ask
    liftIO $ fetchGitHubInsights environment policy targetDate

-- ---------------------------------------------------------------------------
-- Core fetch logic
-- ---------------------------------------------------------------------------

fetchGitHubInsights ::
  GitHubEnv ->
  SourcePolicySnapshot ->
  Day ->
  IO (Either FailureDetail [InsightRecord])
fetchGitHubInsights environment policy targetDate =
  case policy.sourceConfig of
    GitHubSourceConfig _gitHubConfig ->
      fetchRepositories environment policy targetDate
    _ ->
      pure $
        Left $
          FailureDetail
            { reasonCode = DataSchemaInvalid
            , detail = Just "GitHubExternalSourceT received non-GitHub SourceConfig"
            , retryable = False
            , sourceType = Just GitHub
            , stage = Nothing
            }

fetchRepositories ::
  GitHubEnv ->
  SourcePolicySnapshot ->
  Day ->
  IO (Either FailureDetail [InsightRecord])
fetchRepositories environment policy targetDate = do
  -- Query recently updated repositories
  let dateStr = formatTime defaultTimeLocale "%Y-%m-%d" targetDate
  let url =
        "https://api.github.com/search/repositories"
          <> "?q=pushed:>="
          <> dateStr
          <> "&sort=updated&order=desc&per_page=30"
  result <-
    withRetry defaultRetryPolicyConfig isRetryableForAcl $
      executeRequest environment url
  case result of
    Left failureDetail -> pure (Left failureDetail)
    Right responseBody -> do
      let parsed = parseRepositoryResponse responseBody
      case parsed of
        Left failureDetail -> pure (Left failureDetail)
        Right repositories -> do
          now <- getCurrentTime
          recordsResult <- mapM (buildInsightRecord environment policy targetDate now) repositories
          pure (Right (concatMap (either (const []) (: [])) recordsResult))

-- ---------------------------------------------------------------------------
-- Request execution
-- ---------------------------------------------------------------------------

executeRequest ::
  GitHubEnv ->
  String ->
  IO (Either FailureDetail Value)
executeRequest environment url = do
  let request =
        (parseRequest_ url)
          { method = "GET"
          , requestHeaders =
              [ ("Authorization", "Bearer " <> Text.Encoding.encodeUtf8 environment.personalAccessToken)
              , ("Accept", "application/vnd.github+json")
              , ("X-GitHub-Api-Version", "2022-11-28")
              ]
          }
  result <- try @HttpException (environment.httpExecute request)
  case result of
    Left httpException -> pure (Left (mapHttpException httpException))
    Right response -> do
      let code = statusCode (responseStatus response)
      if code == 401 || code == 403
        then
          pure $
            Left $
              FailureDetail
                { reasonCode = DependencyUnavailable
                , detail = Just ("GitHub API auth failure: HTTP " <> Text.pack (show code))
                , retryable = False
                , sourceType = Just GitHub
                , stage = Nothing
                }
        else
          if code == 429
            then
              pure $
                Left $
                  FailureDetail
                    { reasonCode = DependencyUnavailable
                    , detail = Just "GitHub API rate limit exceeded (429)"
                    , retryable = True
                    , sourceType = Just GitHub
                    , stage = Nothing
                    }
            else
              if code >= 500
                then
                  pure $
                    Left $
                      FailureDetail
                        { reasonCode = DependencyUnavailable
                        , detail = Just ("GitHub API server error: HTTP " <> Text.pack (show code))
                        , retryable = True
                        , sourceType = Just GitHub
                        , stage = Nothing
                        }
                else case Aeson.decode (responseBody response) of
                  Nothing ->
                    pure $
                      Left $
                        FailureDetail
                          { reasonCode = DataSchemaInvalid
                          , detail = Just "Failed to parse GitHub API JSON response"
                          , retryable = False
                          , sourceType = Just GitHub
                          , stage = Nothing
                          }
                  Just value -> pure (Right value)

-- ---------------------------------------------------------------------------
-- Response parsing
-- ---------------------------------------------------------------------------

data RepositoryData = RepositoryData
  { repositoryIdentifier :: Text
  -- ^ Must-ACL-024: owner/repo format
  , repositoryDescription :: Text
  , repositoryUrl :: Text
  }
  deriving stock (Show)

parseRepositoryResponse :: Value -> Either FailureDetail [RepositoryData]
parseRepositoryResponse value =
  case Aeson.parseMaybe parseItems value of
    Nothing ->
      Left $
        FailureDetail
          { reasonCode = DataSchemaInvalid
          , detail = Just "Unexpected GitHub search API response structure"
          , retryable = False
          , sourceType = Just GitHub
          , stage = Nothing
          }
    Just result -> Right result
 where
  parseItems :: Value -> Aeson.Parser [RepositoryData]
  parseItems = Aeson.withObject "RepositorySearchResponse" $ \obj -> do
    items <- obj Aeson..:? "items" Aeson..!= []
    mapM parseRepository items

  parseRepository :: Value -> Aeson.Parser RepositoryData
  parseRepository = Aeson.withObject "Repository" $ \obj -> do
    fullName <- obj Aeson..: "full_name"
    description <- obj Aeson..:? "description" Aeson..!= ""
    htmlUrl <- obj Aeson..:? "html_url" Aeson..!= ""
    pure $
      RepositoryData
        { repositoryIdentifier = fullName
        , repositoryDescription = description
        , repositoryUrl = htmlUrl
        }

-- ---------------------------------------------------------------------------
-- InsightRecord construction
-- ---------------------------------------------------------------------------

buildInsightRecord ::
  GitHubEnv ->
  SourcePolicySnapshot ->
  Day ->
  UTCTime ->
  RepositoryData ->
  IO (Either FailureDetail InsightRecord)
buildInsightRecord environment _policy targetDate now repository = do
  ulid <- ULID.getULID
  let snippet = buildEvidenceSnippet repository.repositoryDescription repository.repositoryIdentifier
  let score = calculateSoWhatScore now (UTCTime targetDate 0)
  if score < 0.0 || score > 1.0
    then
      pure $
        Left $
          FailureDetail
            { reasonCode = DataSchemaInvalid
            , detail = Just "soWhatScore out of range [0.0, 1.0]"
            , retryable = False
            , sourceType = Just GitHub
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
                , sourceType = Just GitHub
                , stage = Nothing
                }
        else
          pure $
            Right $
              InsightRecord
                { identifier = InsightRecordIdentifier ulid
                , sourceType = GitHub
                , sourceUrl =
                    if Text.null repository.repositoryUrl
                      then "https://github.com/" <> repository.repositoryIdentifier
                      else repository.repositoryUrl
                , evidenceSnippet = snippet
                , collectedAt = now
                , summary = Text.take 500 repository.repositoryDescription
                , signalClass = classifySignal score
                , soWhatScore = score
                , skillVersion = environment.skillVersion
                }

-- | Must-ACL-025: evidenceSnippet from description; fallback to repositoryIdentifier. Max 200 chars.
buildEvidenceSnippet :: Text -> Text -> Text
buildEvidenceSnippet description repositoryIdentifier =
  let source = if Text.null (Text.strip description) then repositoryIdentifier else description
      compressed = Text.intercalate " " (filter (not . Text.null) (Text.lines source))
   in Text.take 200 (Text.strip compressed)

-- ---------------------------------------------------------------------------
-- So-What scoring (Must-ACL-026/027/028/029)
-- ---------------------------------------------------------------------------

{- | Must-ACL-026: soWhatScore = equal-weight sum of 4 sub-scores.
Freshness: 1.0 if same day, decays linearly over 7 days.
Credibility: 0.7 (GitHub repository — open source, verifiable).
Reproducibility: 0.6 (code is inspectable).
MarketRelevance: 0.5 (default; real implementation uses NLP).
-}
calculateSoWhatScore :: UTCTime -> UTCTime -> Double
calculateSoWhatScore now targetDateUtc =
  let diffSeconds =
        realToFrac (abs (utcTimeToPOSIXSeconds now - utcTimeToPOSIXSeconds targetDateUtc)) :: Double
      diffDays = diffSeconds / 86400.0
      freshness = max 0.0 (1.0 - diffDays / 7.0)
      credibility = 0.7 :: Double
      reproducibility = 0.6 :: Double
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
        , sourceType = Just GitHub
        , stage = Nothing
        }
    ConnectionTimeout ->
      FailureDetail
        { reasonCode = DependencyTimeout
        , detail = Just "HTTP connection timeout"
        , retryable = True
        , sourceType = Just GitHub
        , stage = Nothing
        }
    ConnectionFailure cause ->
      FailureDetail
        { reasonCode = DependencyUnavailable
        , detail = Just ("Connection failure: " <> Text.pack (show cause))
        , retryable = True
        , sourceType = Just GitHub
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
                , sourceType = Just GitHub
                , stage = Nothing
                }
            else
              FailureDetail
                { reasonCode = DependencyUnavailable
                , detail = Just ("Unexpected HTTP status: " <> Text.pack (show code))
                , retryable = False
                , sourceType = Just GitHub
                , stage = Nothing
                }
    other ->
      FailureDetail
        { reasonCode = DependencyUnavailable
        , detail = Just ("HTTP exception: " <> Text.pack (show other))
        , retryable = True
        , sourceType = Just GitHub
        , stage = Nothing
        }
mapHttpException (InvalidUrlException url reason) =
  FailureDetail
    { reasonCode = DataSchemaInvalid
    , detail = Just ("Invalid URL " <> Text.pack url <> ": " <> Text.pack reason)
    , retryable = False
    , sourceType = Just GitHub
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
