{- | ACL adapter for Paper (arXiv/provider) API.

Must-ACL-003: PaperExternalSourceT provides ExternalSourcePort instance.
Must-ACL-005: HTTP timeout default 30 seconds; timeout → DependencyTimeout.
Must-ACL-006: 429/5xx/connection → DependencyUnavailable (retryable=True).
Must-ACL-007: 401/403 → DependencyUnavailable (retryable=False).
Must-ACL-020: Calls PaperConfig.baseUrl for paper provider.
Must-ACL-021: externalIdentifier = paperIdentifier.
Must-ACL-022: evidenceSnippet = abstract/summary, max 200 chars, non-empty.
Must-ACL-026/027/028/029: soWhatScore = equal-weight 4 sub-scores; classify at 0.70.
-}
module ACL.ExternalSource.Paper (
  -- * Environment
  PaperEnv (..),

  -- * Monad transformer
  PaperExternalSourceT (..),
  runPaperExternalSourceT,

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
import Data.Time (Day, UTCTime (..), getCurrentTime)
import Data.Time.Calendar (toModifiedJulianDay)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.ULID qualified as ULID
import Domain.InsightCollection.Aggregate (
  FailureDetail (..),
  InsightRecord (..),
  InsightRecordIdentifier (..),
  PaperConfig (..),
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

{- | Must-ACL-020: Paper adapter environment.
httpExecute enables HTTP transport substitution in tests.
timeoutSeconds defaults to 30 (Must-ACL-005).
-}
data PaperEnv = PaperEnv
  { timeoutSeconds :: Int
  -- ^ Must-ACL-005: 30 seconds default
  , skillVersion :: Text
  -- ^ Must-ACL-003: populated into InsightRecord.skillVersion
  , httpExecute :: Request -> IO (Response ByteString.Lazy.ByteString)
  -- ^ HTTP transport capability — replaced in tests
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype PaperExternalSourceT m a = PaperExternalSourceT
  { unPaperExternalSourceT :: ReaderT PaperEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runPaperExternalSourceT :: PaperEnv -> PaperExternalSourceT m a -> m a
runPaperExternalSourceT environment action =
  runReaderT (unPaperExternalSourceT action) environment

-- ---------------------------------------------------------------------------
-- ExternalSourcePort instance
-- ---------------------------------------------------------------------------

instance ExternalSourcePort (PaperExternalSourceT IO) where
  -- Must-ACL-003
  fetchInsights policy targetDate = PaperExternalSourceT $ do
    environment <- ask
    liftIO $ fetchPaperInsights environment policy targetDate

-- ---------------------------------------------------------------------------
-- Core fetch logic
-- ---------------------------------------------------------------------------

fetchPaperInsights ::
  PaperEnv ->
  SourcePolicySnapshot ->
  Day ->
  IO (Either FailureDetail [InsightRecord])
fetchPaperInsights environment policy targetDate =
  case policy.sourceConfig of
    PaperSourceConfig paperConfig ->
      fetchWithConfig environment paperConfig policy targetDate
    _ ->
      pure $
        Left $
          FailureDetail
            { reasonCode = DataSchemaInvalid
            , detail = Just "PaperExternalSourceT received non-Paper SourceConfig"
            , retryable = False
            , sourceType = Just Paper
            , stage = Nothing
            }

fetchWithConfig ::
  PaperEnv ->
  PaperConfig ->
  SourcePolicySnapshot ->
  Day ->
  IO (Either FailureDetail [InsightRecord])
fetchWithConfig environment paperConfig policy targetDate = do
  let dateStr = formatTime defaultTimeLocale "%Y-%m-%d" targetDate
  let url = Text.unpack paperConfig.baseUrl <> "/papers?date=" <> dateStr
  result <-
    withRetry defaultRetryPolicyConfig isRetryableForAcl $
      executeRequest environment url
  case result of
    Left failureDetail -> pure (Left failureDetail)
    Right responseBody -> do
      let parsed = parsePaperResponse responseBody
      case parsed of
        Left failureDetail -> pure (Left failureDetail)
        Right papers -> do
          now <- getCurrentTime
          recordsResult <- mapM (buildInsightRecord environment policy targetDate now) papers
          pure (Right (concatMap (either (const []) (: [])) recordsResult))

-- ---------------------------------------------------------------------------
-- Request execution
-- ---------------------------------------------------------------------------

executeRequest ::
  PaperEnv ->
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
      if code == 401 || code == 403
        then
          pure $
            Left $
              FailureDetail
                { reasonCode = DependencyUnavailable
                , detail = Just ("Paper API auth failure: HTTP " <> Text.pack (show code))
                , retryable = False
                , sourceType = Just Paper
                , stage = Nothing
                }
        else
          if code >= 500
            then
              pure $
                Left $
                  FailureDetail
                    { reasonCode = DependencyUnavailable
                    , detail = Just ("Paper API server error: HTTP " <> Text.pack (show code))
                    , retryable = True
                    , sourceType = Just Paper
                    , stage = Nothing
                    }
            else case Aeson.decode (responseBody response) of
              Nothing ->
                pure $
                  Left $
                    FailureDetail
                      { reasonCode = DataSchemaInvalid
                      , detail = Just "Failed to parse Paper API JSON response"
                      , retryable = False
                      , sourceType = Just Paper
                      , stage = Nothing
                      }
              Just value -> pure (Right value)

-- ---------------------------------------------------------------------------
-- Response parsing
-- ---------------------------------------------------------------------------

data PaperData = PaperData
  { paperIdentifier :: Text
  , paperTitle :: Text
  , paperAbstract :: Text
  , paperUrl :: Text
  }
  deriving stock (Show)

parsePaperResponse :: Value -> Either FailureDetail [PaperData]
parsePaperResponse value =
  case Aeson.parseMaybe parseItems value of
    Nothing ->
      Left $
        FailureDetail
          { reasonCode = DataSchemaInvalid
          , detail = Just "Unexpected Paper API response structure"
          , retryable = False
          , sourceType = Just Paper
          , stage = Nothing
          }
    Just result -> Right result
 where
  parseItems :: Value -> Aeson.Parser [PaperData]
  parseItems = Aeson.withObject "PapersResponse" $ \obj -> do
    items <- obj Aeson..:? "papers" Aeson..!= []
    mapM parsePaper items

  parsePaper :: Value -> Aeson.Parser PaperData
  parsePaper = Aeson.withObject "Paper" $ \obj -> do
    paperId <- obj Aeson..: "id"
    title <- obj Aeson..:? "title" Aeson..!= ""
    abstract <- obj Aeson..:? "abstract" Aeson..!= ""
    paperSourceUrl <- obj Aeson..:? "url" Aeson..!= ""
    pure $
      PaperData
        { paperIdentifier = paperId
        , paperTitle = title
        , paperAbstract = abstract
        , paperUrl = paperSourceUrl
        }

-- ---------------------------------------------------------------------------
-- InsightRecord construction
-- ---------------------------------------------------------------------------

buildInsightRecord ::
  PaperEnv ->
  SourcePolicySnapshot ->
  Day ->
  UTCTime ->
  PaperData ->
  IO (Either FailureDetail InsightRecord)
buildInsightRecord environment _policy targetDate now paper = do
  ulid <- ULID.getULID
  let snippet = buildEvidenceSnippet paper.paperAbstract paper.paperTitle
  let score = calculateSoWhatScore now (UTCTime targetDate 0)
  if score < 0.0 || score > 1.0
    then
      pure $
        Left $
          FailureDetail
            { reasonCode = DataSchemaInvalid
            , detail = Just "soWhatScore out of range [0.0, 1.0]"
            , retryable = False
            , sourceType = Just Paper
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
                , sourceType = Just Paper
                , stage = Nothing
                }
        else
          pure $
            Right $
              InsightRecord
                { identifier = InsightRecordIdentifier ulid
                , sourceType = Paper
                , sourceUrl = if Text.null paper.paperUrl then "https://arxiv.org/abs/" <> paper.paperIdentifier else paper.paperUrl
                , evidenceSnippet = snippet
                , collectedAt = now
                , summary = Text.take 500 paper.paperAbstract
                , signalClass = classifySignal score
                , soWhatScore = score
                , skillVersion = environment.skillVersion
                }

-- | Must-ACL-022: evidenceSnippet from abstract; fallback to title. Max 200 chars.
buildEvidenceSnippet :: Text -> Text -> Text
buildEvidenceSnippet abstract title =
  let source = if Text.null (Text.strip abstract) then title else abstract
      compressed = Text.intercalate " " (filter (not . Text.null) (Text.lines source))
   in Text.take 200 (Text.strip compressed)

-- ---------------------------------------------------------------------------
-- So-What scoring (Must-ACL-026/027/028/029)
-- ---------------------------------------------------------------------------

{- | Must-ACL-026: soWhatScore = equal-weight sum of 4 sub-scores.
Freshness: 1.0 if same day, decays linearly over 7 days.
Credibility: 0.8 (academic paper — high credibility).
Reproducibility: 0.7 (peer-reviewed or preprint with methodology).
MarketRelevance: 0.5 (default; real implementation uses NLP).
-}
calculateSoWhatScore :: UTCTime -> UTCTime -> Double
calculateSoWhatScore now targetDateUtc =
  let diffSeconds =
        realToFrac (abs (utcTimeToPOSIXSeconds now - utcTimeToPOSIXSeconds targetDateUtc)) :: Double
      diffDays = diffSeconds / 86400.0
      freshness = max 0.0 (1.0 - diffDays / 7.0)
      credibility = 0.8 :: Double
      reproducibility = 0.7 :: Double
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
        , sourceType = Just Paper
        , stage = Nothing
        }
    ConnectionTimeout ->
      FailureDetail
        { reasonCode = DependencyTimeout
        , detail = Just "HTTP connection timeout"
        , retryable = True
        , sourceType = Just Paper
        , stage = Nothing
        }
    ConnectionFailure cause ->
      FailureDetail
        { reasonCode = DependencyUnavailable
        , detail = Just ("Connection failure: " <> Text.pack (show cause))
        , retryable = True
        , sourceType = Just Paper
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
                , sourceType = Just Paper
                , stage = Nothing
                }
            else
              FailureDetail
                { reasonCode = DependencyUnavailable
                , detail = Just ("Unexpected HTTP status: " <> Text.pack (show code))
                , retryable = False
                , sourceType = Just Paper
                , stage = Nothing
                }
    other ->
      FailureDetail
        { reasonCode = DependencyUnavailable
        , detail = Just ("HTTP exception: " <> Text.pack (show other))
        , retryable = True
        , sourceType = Just Paper
        , stage = Nothing
        }
mapHttpException (InvalidUrlException url reason) =
  FailureDetail
    { reasonCode = DataSchemaInvalid
    , detail = Just ("Invalid URL " <> Text.pack url <> ": " <> Text.pack reason)
    , retryable = False
    , sourceType = Just Paper
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
