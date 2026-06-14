{- | ACL adapter for J-Quants REST API.

Must-01: JQuantsMarketDataSourceT provides MarketDataSource instance.
Must-04: Calls GET /listed/info and GET /prices/daily_quotes with Bearer auth.
Must-05: Handles pagination_key.
Must-06: Maps §8.2.1 adoption columns into RawMarketRecord.fields.
Must-07: AdjustmentFactor <= 0 or null → DataSchemaInvalid.
Must-08: No adjusted-price recalculation in ACL layer (raw values only).
Must-15: 30-second timeout per request.
Must-16: withRetry wraps HTTP; isRetryableForAcl exported.
Must-17: Timeout → DataSourceTimeout.
Must-18: 5xx / connection failure → DataSourceUnavailable.
Must-19: Parse errors → DataSchemaInvalid.
Must-20: Only api.jquants-pro.com/v2 endpoints used.
-}
module Infrastructure.ACL.JQuantsMarketDataSourceT (
  -- * Environment
  JQuantsEnv (..),

  -- * Monad transformer
  JQuantsMarketDataSourceT (..),
  runJQuantsMarketDataSourceT,

  -- * Retry predicate (exported for tests — Must-16)
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
import Data.Time (Day)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Domain.MarketCollection.Aggregate (FailureDetail (..))
import Domain.MarketCollection.CollectionQualityPolicy (RawMarketField (..), RawMarketRecord (..))
import Domain.MarketCollection.MarketDataSource (MarketDataSource (..))
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Infrastructure.ACL.NisshokinCsvSourceAdapter (NisshokinEnv (..), fetchNisshokinCsvData)
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

{- | Must-04: J-Quants adapter environment.
baseUrl defaults to https://api.jquants-pro.com/v2.
timeoutSeconds defaults to 30 (Must-15).
httpExecute enables HTTP transport substitution in tests (Must-21 test design).
-}
data JQuantsEnv = JQuantsEnv
  { baseUrl :: Text
  -- ^ Must-04/Must-20: https://api.jquants-pro.com/v2
  , idToken :: Text
  -- ^ Must-04: Bearer token from Secret Manager / env var
  , timeoutSeconds :: Int
  -- ^ Must-15: 30 seconds per request
  , httpExecute :: Request -> IO (Response ByteString.Lazy.ByteString)
  -- ^ HTTP transport capability — replaced in tests
  , nisshokinEnv :: NisshokinEnv
  -- ^ Must-03: Nisshokin adapter invoked inside fetchJapanMarketData
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype JQuantsMarketDataSourceT m a = JQuantsMarketDataSourceT
  { unJQuantsMarketDataSourceT :: ReaderT JQuantsEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runJQuantsMarketDataSourceT :: JQuantsEnv -> JQuantsMarketDataSourceT m a -> m a
runJQuantsMarketDataSourceT environment action =
  runReaderT (unJQuantsMarketDataSourceT action) environment

-- ---------------------------------------------------------------------------
-- MarketDataSource instance
-- ---------------------------------------------------------------------------

instance MarketDataSource (JQuantsMarketDataSourceT IO) where
  -- Must-01/Must-04/Must-05/Must-06/Must-07/Must-08
  fetchJapanMarketData targetDate = JQuantsMarketDataSourceT $ do
    environment <- ask
    liftIO $ fetchJapanMarketDataIO environment targetDate

  -- Must-01: fetchUsMarketData is unused in J-Quants adapter; returns empty success.
  fetchUsMarketData _ = JQuantsMarketDataSourceT $ pure (Right [])

-- ---------------------------------------------------------------------------
-- Core fetch logic
-- ---------------------------------------------------------------------------

fetchJapanMarketDataIO ::
  JQuantsEnv ->
  Day ->
  IO (Either FailureDetail [RawMarketRecord])
fetchJapanMarketDataIO environment targetDate = do
  let dateString = formatDay targetDate
  -- Fetch listed/info and daily_quotes, then merge
  listedResult <-
    withRetry defaultRetryPolicyConfig isRetryableForAcl $
      fetchListedInfo environment dateString
  case listedResult of
    Left failure -> pure (Left failure)
    Right listedRecords -> do
      quotesResult <-
        withRetry defaultRetryPolicyConfig isRetryableForAcl $
          fetchAllDailyQuotes environment dateString Nothing []
      case quotesResult of
        Left failure -> pure (Left failure)
        Right quoteRecords -> do
          -- Must-03: Invoke Nisshokin adapter internally
          nisshokinResult <- fetchNisshokinCsvData environment.nisshokinEnv targetDate
          case nisshokinResult of
            Left failure -> pure (Left failure)
            Right nisshokinRecords ->
              pure (Right (listedRecords ++ quoteRecords ++ nisshokinRecords))

-- | Must-04: GET /listed/info?date=YYYY-MM-DD
fetchListedInfo ::
  JQuantsEnv ->
  String ->
  IO (Either FailureDetail [RawMarketRecord])
fetchListedInfo environment dateString = do
  let url = Text.unpack environment.baseUrl <> "/listed/info?date=" <> dateString
  executeRequest environment url decodeListedInfo

-- | Must-05: GET /prices/daily_quotes with pagination_key loop
fetchAllDailyQuotes ::
  JQuantsEnv ->
  String ->
  Maybe Text ->
  [RawMarketRecord] ->
  IO (Either FailureDetail [RawMarketRecord])
fetchAllDailyQuotes environment dateString maybePaginationKey accumulated = do
  let baseUrl = Text.unpack environment.baseUrl <> "/prices/daily_quotes?date=" <> dateString
      url = case maybePaginationKey of
        Nothing -> baseUrl
        Just key -> baseUrl <> "&pagination_key=" <> Text.unpack key
  result <- executeRequest environment url decodeDailyQuotes
  case result of
    Left failure -> pure (Left failure)
    Right (records, nextKey) ->
      let allRecords = accumulated ++ records
       in case nextKey of
            Nothing -> pure (Right allRecords)
            Just key -> fetchAllDailyQuotes environment dateString (Just key) allRecords

-- ---------------------------------------------------------------------------
-- HTTP execution
-- ---------------------------------------------------------------------------

executeRequest ::
  JQuantsEnv ->
  String ->
  (Value -> Either FailureDetail a) ->
  IO (Either FailureDetail a)
executeRequest environment url decode = do
  let request =
        (parseRequest_ url)
          { method = "GET"
          , requestHeaders =
              [ ("Authorization", "Bearer " <> Text.Encoding.encodeUtf8 environment.idToken)
              ]
          }
  responseResult <- try @HttpException (environment.httpExecute request)
  case responseResult of
    Left httpException -> pure (Left (mapHttpException httpException))
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
        else case Aeson.decode (responseBody response) of
          Nothing ->
            pure
              ( Left
                  FailureDetail
                    { reasonCode = DataSchemaInvalid
                    , detail = Just "Failed to decode JSON response"
                    , retryable = False
                    }
              )
          Just jsonValue -> pure (decode jsonValue)

-- ---------------------------------------------------------------------------
-- Response decoders
-- ---------------------------------------------------------------------------

-- | Decode /listed/info response into RawMarketRecord list (Must-06 text fields)
decodeListedInfo :: Value -> Either FailureDetail [RawMarketRecord]
decodeListedInfo value =
  case Aeson.parseEither parseListedInfoResponse value of
    Left parseError ->
      Left
        FailureDetail
          { reasonCode = DataSchemaInvalid
          , detail = Just (Text.pack parseError)
          , retryable = False
          }
    Right records -> Right records

parseListedInfoResponse :: Value -> Aeson.Parser [RawMarketRecord]
parseListedInfoResponse = Aeson.withObject "ListedInfoResponse" $ \object -> do
  infos <- object Aeson..: "info"
  mapM parseListedInfoRecord infos

parseListedInfoRecord :: Value -> Aeson.Parser RawMarketRecord
parseListedInfoRecord = Aeson.withObject "ListedInfo" $ \object -> do
  dateText <- object Aeson..: "Date"
  codeText <- object Aeson..: "Code"
  marketCode <- object Aeson..:? "MarketCode" Aeson..!= ""
  marketCodeName <- object Aeson..:? "MarketCodeName" Aeson..!= ""
  sector17Code <- object Aeson..:? "Sector17Code" Aeson..!= ""
  sector33Code <- object Aeson..:? "Sector33Code" Aeson..!= ""
  scaleCategory <- object Aeson..:? "ScaleCategory" Aeson..!= ""
  marginCode <- object Aeson..:? "MarginCode" Aeson..!= ""
  pure
    RawMarketRecord
      { fields =
          [ ("Date", FieldText dateText)
          , ("Code", FieldText codeText)
          , ("MarketCode", FieldText marketCode)
          , ("MarketCodeName", FieldText marketCodeName)
          , ("Sector17Code", FieldText sector17Code)
          , ("Sector33Code", FieldText sector33Code)
          , ("ScaleCategory", FieldText scaleCategory)
          , ("MarginCode", FieldText marginCode)
          ]
      }

-- | Decode /prices/daily_quotes response — Must-06 + Must-05 pagination_key
decodeDailyQuotes :: Value -> Either FailureDetail ([RawMarketRecord], Maybe Text)
decodeDailyQuotes value =
  case Aeson.parseEither parseDailyQuotesResponse value of
    Left parseError ->
      Left
        FailureDetail
          { reasonCode = DataSchemaInvalid
          , detail = Just (Text.pack parseError)
          , retryable = False
          }
    Right result -> Right result

parseDailyQuotesResponse :: Value -> Aeson.Parser ([RawMarketRecord], Maybe Text)
parseDailyQuotesResponse = Aeson.withObject "DailyQuotesResponse" $ \object -> do
  quotes <- object Aeson..: "daily_quotes"
  maybePaginationKey <- object Aeson..:? "pagination_key"
  records <- mapM parseDailyQuoteRecord quotes
  pure (records, maybePaginationKey)

-- | Must-06: Parse one daily_quote row; Must-07: AdjustmentFactor <= 0 or null → error
parseDailyQuoteRecord :: Value -> Aeson.Parser RawMarketRecord
parseDailyQuoteRecord = Aeson.withObject "DailyQuote" $ \object -> do
  dateText <- object Aeson..: "Date"
  codeText <- object Aeson..: "Code"
  -- Must-07: AdjustmentFactor must be present and > 0
  maybeAdjustmentFactor <- object Aeson..:? "AdjustmentFactor"
  adjustmentFactor <- case maybeAdjustmentFactor of
    Nothing ->
      fail "AdjustmentFactor is missing"
    Just factorValue ->
      if (factorValue :: Double) <= 0
        then fail "AdjustmentFactor must be > 0"
        else pure factorValue
  -- Numeric fields — Must-06 FieldDouble
  openValue <- object Aeson..:? "Open" Aeson..!= 0.0
  highValue <- object Aeson..:? "High" Aeson..!= 0.0
  lowValue <- object Aeson..:? "Low" Aeson..!= 0.0
  closeValue <- object Aeson..:? "Close" Aeson..!= 0.0
  volume <- object Aeson..:? "Volume" Aeson..!= (0.0 :: Double)
  turnoverValue <- object Aeson..:? "TurnoverValue" Aeson..!= 0.0
  adjustmentOpen <- object Aeson..:? "AdjustmentOpen" Aeson..!= 0.0
  adjustmentHigh <- object Aeson..:? "AdjustmentHigh" Aeson..!= 0.0
  adjustmentLow <- object Aeson..:? "AdjustmentLow" Aeson..!= 0.0
  adjustmentClose <- object Aeson..:? "AdjustmentClose" Aeson..!= 0.0
  adjustmentVolume <- object Aeson..:? "AdjustmentVolume" Aeson..!= 0.0
  pure
    RawMarketRecord
      { fields =
          [ ("Date", FieldText dateText)
          , ("Code", FieldText codeText)
          , ("Open", FieldDouble openValue)
          , ("High", FieldDouble highValue)
          , ("Low", FieldDouble lowValue)
          , ("Close", FieldDouble closeValue)
          , ("Volume", FieldDouble volume)
          , ("TurnoverValue", FieldDouble turnoverValue)
          , ("AdjustmentFactor", FieldDouble adjustmentFactor)
          , ("AdjustmentOpen", FieldDouble adjustmentOpen)
          , ("AdjustmentHigh", FieldDouble adjustmentHigh)
          , ("AdjustmentLow", FieldDouble adjustmentLow)
          , ("AdjustmentClose", FieldDouble adjustmentClose)
          , ("AdjustmentVolume", FieldDouble adjustmentVolume)
          ]
      }

-- ---------------------------------------------------------------------------
-- Error mapping
-- ---------------------------------------------------------------------------

-- | Must-17/Must-18: Map HttpException to FailureDetail
mapHttpException :: HttpException -> FailureDetail
mapHttpException (HttpExceptionRequest _ exceptionContent) =
  case exceptionContent of
    ResponseTimeout ->
      FailureDetail
        { reasonCode = DataSourceTimeout
        , detail = Just "HTTP response timeout"
        , retryable = True
        }
    ConnectionTimeout ->
      FailureDetail
        { reasonCode = DataSourceTimeout
        , detail = Just "HTTP connection timeout"
        , retryable = True
        }
    ConnectionFailure cause ->
      FailureDetail
        { reasonCode = DataSourceUnavailable
        , detail = Just ("Connection failure: " <> Text.pack (show cause))
        , retryable = True
        }
    StatusCodeException response _ ->
      let statusCodeValue = statusCode (responseStatus response)
       in if statusCodeValue >= 500
            then
              FailureDetail
                { reasonCode = DataSourceUnavailable
                , detail = Just ("HTTP " <> Text.pack (show statusCodeValue))
                , retryable = True
                }
            else
              FailureDetail
                { reasonCode = DataSchemaInvalid
                , detail = Just ("Unexpected HTTP status: " <> Text.pack (show statusCodeValue))
                , retryable = False
                }
    other ->
      FailureDetail
        { reasonCode = DataSourceUnavailable
        , detail = Just ("HTTP exception: " <> Text.pack (show other))
        , retryable = True
        }
mapHttpException (InvalidUrlException url reason) =
  FailureDetail
    { reasonCode = DataSchemaInvalid
    , detail = Just ("Invalid URL " <> Text.pack url <> ": " <> Text.pack reason)
    , retryable = False
    }

-- ---------------------------------------------------------------------------
-- Retry predicate
-- ---------------------------------------------------------------------------

{- | Must-16: Retry predicate for ACL layer.
Returns (.retryable) field of FailureDetail.
Exported so test suites can verify TC-ACL-011.
-}
isRetryableForAcl :: FailureDetail -> Bool
isRetryableForAcl failureDetail = failureDetail.retryable

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

formatDay :: Day -> String
formatDay = formatTime defaultTimeLocale "%Y-%m-%d"
