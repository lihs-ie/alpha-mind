{- | ACL adapter for Nisshokin (日商金) CSV data source.

Must-03: fetchNisshokinCsvData is an internal sub-call from fetchJapanMarketData.
Must-12: URL direct → 2 attempts → browserFallback capability (injected).
Must-13: Required columns validation → DataSchemaInvalid if missing.
Must-14: Logs browser_fallback when fallback is invoked.
Must-15: 60-second timeout per request.
Must-17/Must-18/Must-19: Error mapping to FailureDetail.
Must-20: Only Nisshokin domain endpoint accessed.
-}
module Infrastructure.ACL.NisshokinCsvSourceAdapter (
  -- * Environment
  NisshokinEnv (..),

  -- * Adapter function (Must-03)
  fetchNisshokinCsvData,
) where

import Control.Exception (try)
import Data.Bifunctor (second)
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time (Day)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Domain.MarketCollection.Aggregate (FailureDetail (..))
import Domain.MarketCollection.CollectionQualityPolicy (RawMarketField (..), RawMarketRecord (..))
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
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

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

{- | Must-12: Nisshokin adapter environment.
httpExecute is the HTTP transport capability (replaceable in tests).
browserFallback is the injected capability for browser automation (Must-12).
onBrowserFallback is the injected logging capability for Must-14 (本番 katip 配線は #28).
timeoutSeconds defaults to 60 (Must-15).
-}
data NisshokinEnv = NisshokinEnv
  { timeoutSeconds :: Int
  -- ^ Must-15: 60 seconds per request
  , httpExecute :: Request -> IO (Response ByteString.Lazy.ByteString)
  -- ^ HTTP transport capability — replaced in tests
  , browserFallback :: Day -> IO (Either FailureDetail [RawMarketRecord])
  -- ^ Must-12: Browser automation capability — injected, not implemented here
  , onBrowserFallback :: Text -> IO ()
  {- ^ Must-14: Structured log capability for browser_fallback invocation.
  本番 katip 配線は #28。テストでは IORef fake を注入。
  -}
  }

-- ---------------------------------------------------------------------------
-- Required CSV columns (Must-13)
-- ---------------------------------------------------------------------------

{- | Must-13: Required columns in Nisshokin CSV.
Field names: symbol code, target date, lending fee (品貸料).
-}
nisshokinRequiredColumns :: [Text]
nisshokinRequiredColumns = ["銘柄コード", "対象日", "品貸料"]

-- | Must-20: Nisshokin base URL
nisshokinCsvBaseUrl :: String
nisshokinCsvBaseUrl = "https://www.nisshokinen.or.jp/data/"

-- ---------------------------------------------------------------------------
-- Main adapter function
-- ---------------------------------------------------------------------------

{- | Must-03: Fetch Nisshokin CSV data.
Must-12: URL direct 2 attempts → browserFallback → DataSourceUnavailable.
Must-13: Validate required columns.
Must-14: Log browser_fallback when invoked.
-}
fetchNisshokinCsvData ::
  NisshokinEnv ->
  Day ->
  IO (Either FailureDetail [RawMarketRecord])
fetchNisshokinCsvData environment targetDate = do
  -- Attempt 1: URL direct
  attempt1 <- fetchCsvDirect environment targetDate
  case attempt1 of
    Right records -> pure (Right records)
    Left failure1
      -- Must-19: Non-retryable errors (e.g. DataSchemaInvalid) fail immediately.
      | not failure1.retryable -> pure (Left failure1)
      | otherwise -> do
          -- Attempt 2: URL direct (second try)
          attempt2 <- fetchCsvDirect environment targetDate
          case attempt2 of
            Right records -> pure (Right records)
            Left failure2
              | not failure2.retryable -> pure (Left failure2)
              | otherwise -> do
                  -- Must-14: Log browser_fallback invocation via injected capability
                  let dateString = formatTime defaultTimeLocale "%Y-%m-%d" targetDate
                  environment.onBrowserFallback
                    ("reason=browser_fallback targetDate=" <> Text.pack dateString)
                  -- Attempt 3: browserFallback capability
                  environment.browserFallback targetDate

-- ---------------------------------------------------------------------------
-- URL direct fetch
-- ---------------------------------------------------------------------------

fetchCsvDirect ::
  NisshokinEnv ->
  Day ->
  IO (Either FailureDetail [RawMarketRecord])
fetchCsvDirect environment targetDate = do
  let dateString = formatTime defaultTimeLocale "%Y%m%d" targetDate
      url = nisshokinCsvBaseUrl <> dateString <> ".csv"
      request = (parseRequest_ url){method = "GET"}
  responseResult <- try @HttpException (environment.httpExecute request)
  case responseResult of
    Left httpException -> pure (Left (mapNisshokinHttpException httpException))
    Right response -> do
      let statusCodeValue = statusCode (responseStatus response)
      if statusCodeValue >= 500
        then
          pure
            ( Left
                FailureDetail
                  { reasonCode = DataSourceUnavailable
                  , detail = Just ("HTTP " <> Text.pack (show statusCodeValue))
                  , retryable = True
                  }
            )
        else do
          let bodyBytes = ByteString.Lazy.toStrict (responseBody response)
          let bodyText = Text.Encoding.decodeUtf8Lenient bodyBytes
          parseCsvBody bodyText

-- ---------------------------------------------------------------------------
-- CSV parsing (Must-13)
-- ---------------------------------------------------------------------------

parseCsvBody :: Text -> IO (Either FailureDetail [RawMarketRecord])
parseCsvBody csvText = do
  let linesList = Text.lines csvText
  case linesList of
    [] ->
      pure
        ( Left
            FailureDetail
              { reasonCode = DataSchemaInvalid
              , detail = Just "Empty CSV response"
              , retryable = False
              }
        )
    headerLine : dataLines -> do
      let headers = splitCsvLine headerLine
      -- Must-13: Validate required columns
      let missingColumns = filter (`notElem` headers) nisshokinRequiredColumns
      case missingColumns of
        _ : _ ->
          pure
            ( Left
                FailureDetail
                  { reasonCode = DataSchemaInvalid
                  , detail = Just ("Missing required CSV columns: " <> Text.intercalate ", " missingColumns)
                  , retryable = False
                  }
            )
        [] -> do
          let dataRows = filter (not . Text.null . Text.strip) dataLines
          let records = map (buildRecord headers) dataRows
          pure (Right records)

splitCsvLine :: Text -> [Text]
splitCsvLine line = Text.splitOn "," (Text.strip line)

buildRecord :: [Text] -> Text -> RawMarketRecord
buildRecord headers dataLine =
  let values = splitCsvLine dataLine
      pairs = zip headers values
   in RawMarketRecord
        { fields = map (second FieldText) pairs
        }

-- ---------------------------------------------------------------------------
-- Error mapping
-- ---------------------------------------------------------------------------

mapNisshokinHttpException :: HttpException -> FailureDetail
mapNisshokinHttpException (HttpExceptionRequest _ exceptionContent) =
  case exceptionContent of
    ResponseTimeout ->
      FailureDetail
        { reasonCode = DataSourceTimeout
        , detail = Just "Nisshokin HTTP response timeout"
        , retryable = True
        }
    ConnectionTimeout ->
      FailureDetail
        { reasonCode = DataSourceTimeout
        , detail = Just "Nisshokin HTTP connection timeout"
        , retryable = True
        }
    ConnectionFailure cause ->
      FailureDetail
        { reasonCode = DataSourceUnavailable
        , detail = Just ("Nisshokin connection failure: " <> Text.pack (show cause))
        , retryable = True
        }
    other ->
      FailureDetail
        { reasonCode = DataSourceUnavailable
        , detail = Just ("Nisshokin HTTP exception: " <> Text.pack (show other))
        , retryable = True
        }
mapNisshokinHttpException (InvalidUrlException url reason) =
  FailureDetail
    { reasonCode = DataSchemaInvalid
    , detail = Just ("Invalid Nisshokin URL " <> Text.pack url <> ": " <> Text.pack reason)
    , retryable = False
    }
