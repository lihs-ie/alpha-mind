{- | ACL adapter for Alpaca Market Data REST API.

Must-02: AlpacaMarketDataSourceT provides MarketDataSource instance.
Must-09: usCollectionEnabled=False → Right [] (no HTTP).
Must-10: usCollectionEnabled=True → GET /stocks/bars with APCA headers + pagination.
Must-11: Maps §8.2.2 adoption columns (t, o, h, l, c, v, vw, n).
Must-15: 30-second timeout per request.
Must-16: withRetry wraps HTTP; isRetryableForAcl from JQuantsMarketDataSourceT.
Must-17/Must-18/Must-19: Error mapping via FailureDetail.
Must-20: Only data.alpaca.markets/v2 endpoint used.
-}
module Infrastructure.ACL.AlpacaMarketDataSourceT (
  -- * Environment
  AlpacaEnv (..),

  -- * Monad transformer
  AlpacaMarketDataSourceT (..),
  runAlpacaMarketDataSourceT,
) where

import Control.Exception (try)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as Aeson.KeyMap
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
import Infrastructure.ACL.JQuantsMarketDataSourceT (isRetryableForAcl)
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

{- | Must-02/Must-09/Must-10: Alpaca adapter environment.
usCollectionEnabled=False disables HTTP (MVP default).
timeoutSeconds defaults to 30 (Must-15).
baseUrl defaults to https://data.alpaca.markets/v2 (Must-20).
httpExecute enables HTTP transport substitution in tests.
-}
data AlpacaEnv = AlpacaEnv
  { usCollectionEnabled :: Bool
  -- ^ Must-09: MVP default is False
  , apiKeyIdentifier :: Text
  -- ^ Must-10: APCA-API-KEY-ID header value
  , apiSecretKey :: Text
  -- ^ Must-10: APCA-API-SECRET-KEY header value
  , timeoutSeconds :: Int
  -- ^ Must-15: 30 seconds per request
  , baseUrl :: Text
  -- ^ Must-20: https://data.alpaca.markets/v2
  , httpExecute :: Request -> IO (Response ByteString.Lazy.ByteString)
  -- ^ HTTP transport capability — replaced in tests
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype AlpacaMarketDataSourceT m a = AlpacaMarketDataSourceT
  { unAlpacaMarketDataSourceT :: ReaderT AlpacaEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runAlpacaMarketDataSourceT :: AlpacaEnv -> AlpacaMarketDataSourceT m a -> m a
runAlpacaMarketDataSourceT environment action =
  runReaderT (unAlpacaMarketDataSourceT action) environment

-- ---------------------------------------------------------------------------
-- MarketDataSource instance
-- ---------------------------------------------------------------------------

instance MarketDataSource (AlpacaMarketDataSourceT IO) where
  -- Must-02: fetchJapanMarketData not applicable in Alpaca adapter
  fetchJapanMarketData _ = AlpacaMarketDataSourceT $ pure (Right [])

  -- Must-02/Must-09/Must-10
  fetchUsMarketData targetDate = AlpacaMarketDataSourceT $ do
    environment <- ask
    liftIO $ fetchUsMarketDataIO environment targetDate

-- ---------------------------------------------------------------------------
-- Core fetch logic
-- ---------------------------------------------------------------------------

fetchUsMarketDataIO ::
  AlpacaEnv ->
  Day ->
  IO (Either FailureDetail [RawMarketRecord])
fetchUsMarketDataIO environment targetDate
  -- Must-09: usCollectionEnabled=False → no HTTP, return Right []
  | not environment.usCollectionEnabled = pure (Right [])
  -- Must-10: usCollectionEnabled=True → paginate through /stocks/bars
  | otherwise =
      withRetry defaultRetryPolicyConfig isRetryableForAcl $
        fetchAllBars environment targetDate Nothing []

-- | Must-10: GET /stocks/bars with next_page_token pagination
fetchAllBars ::
  AlpacaEnv ->
  Day ->
  Maybe Text ->
  [RawMarketRecord] ->
  IO (Either FailureDetail [RawMarketRecord])
fetchAllBars environment targetDate maybeNextPageToken accumulated = do
  let dateString = formatTime defaultTimeLocale "%Y-%m-%d" targetDate
      baseRequestUrl =
        Text.unpack environment.baseUrl
          <> "/stocks/bars?timeframe=1Day&start="
          <> dateString
          <> "&end="
          <> dateString
      url = case maybeNextPageToken of
        Nothing -> baseRequestUrl
        Just token -> baseRequestUrl <> "&next_page_token=" <> Text.unpack token
      request =
        (parseRequest_ url)
          { method = "GET"
          , requestHeaders =
              [ ("APCA-API-KEY-ID", Text.Encoding.encodeUtf8 environment.apiKeyIdentifier)
              , ("APCA-API-SECRET-KEY", Text.Encoding.encodeUtf8 environment.apiSecretKey)
              ]
          }
  responseResult <- try @HttpException (environment.httpExecute request)
  case responseResult of
    Left httpException -> pure (Left (mapAlpacaHttpException httpException))
    Right response -> do
      let statusCodeValue = statusCode (responseStatus response)
      if statusCodeValue >= 500
        then
          pure
            ( Left
                FailureDetail
                  { reasonCode = DataSourceUnavailable
                  , detail = Just ("Alpaca HTTP " <> Text.pack (show statusCodeValue))
                  , retryable = True
                  }
            )
        else case Aeson.decode (responseBody response) of
          Nothing ->
            pure
              ( Left
                  FailureDetail
                    { reasonCode = DataSchemaInvalid
                    , detail = Just "Failed to decode Alpaca JSON response"
                    , retryable = False
                    }
              )
          Just jsonValue ->
            case decodeBarsResponse jsonValue of
              Left failure -> pure (Left failure)
              Right (records, nextPageToken) ->
                let allRecords = accumulated ++ records
                 in case nextPageToken of
                      Nothing -> pure (Right allRecords)
                      Just token -> fetchAllBars environment targetDate (Just token) allRecords

-- ---------------------------------------------------------------------------
-- Response decoder
-- ---------------------------------------------------------------------------

-- | Must-10/Must-11: Decode /stocks/bars response
decodeBarsResponse :: Value -> Either FailureDetail ([RawMarketRecord], Maybe Text)
decodeBarsResponse value =
  case Aeson.parseEither parseBarsResponse value of
    Left parseError ->
      Left
        FailureDetail
          { reasonCode = DataSchemaInvalid
          , detail = Just (Text.pack parseError)
          , retryable = False
          }
    Right result -> Right result

parseBarsResponse :: Value -> Aeson.Parser ([RawMarketRecord], Maybe Text)
parseBarsResponse = Aeson.withObject "BarsResponse" $ \object -> do
  barsMap <- object Aeson..: "bars"
  nextPageToken <- object Aeson..:? "next_page_token"
  records <- parseAllSymbolBars barsMap
  pure (records, nextPageToken)

parseAllSymbolBars :: Value -> Aeson.Parser [RawMarketRecord]
parseAllSymbolBars = Aeson.withObject "BarsMap" $ \object -> do
  let symbolEntries = Aeson.KeyMap.toAscList object
  concat <$> mapM parseSymbolBarsEntry symbolEntries

parseSymbolBarsEntry :: (Aeson.Key, Value) -> Aeson.Parser [RawMarketRecord]
parseSymbolBarsEntry (_, barsValue) =
  Aeson.withArray "BarList" (mapM parseBarRecord . foldr (:) []) barsValue

-- | Must-11: Parse one bar record — fields t, o, h, l, c, v, vw, n
parseBarRecord :: Value -> Aeson.Parser RawMarketRecord
parseBarRecord = Aeson.withObject "Bar" $ \object -> do
  timestamp <- object Aeson..: "t"
  openValue <- object Aeson..: "o"
  highValue <- object Aeson..: "h"
  lowValue <- object Aeson..: "l"
  closeValue <- object Aeson..: "c"
  volume <- object Aeson..: "v"
  maybeVolumeWeighted <- object Aeson..:? "vw"
  maybeTradeCount <- object Aeson..:? "n"
  let baseFields =
        [ ("t", FieldText timestamp)
        , ("o", FieldDouble openValue)
        , ("h", FieldDouble highValue)
        , ("l", FieldDouble lowValue)
        , ("c", FieldDouble closeValue)
        , ("v", FieldDouble volume)
        ]
      optionalFields =
        [ maybe [] (\vw -> [("vw", FieldDouble vw)]) maybeVolumeWeighted
        , maybe [] (\n -> [("n", FieldInt n)]) maybeTradeCount
        ]
  pure RawMarketRecord{fields = baseFields ++ concat optionalFields}

-- ---------------------------------------------------------------------------
-- Error mapping
-- ---------------------------------------------------------------------------

mapAlpacaHttpException :: HttpException -> FailureDetail
mapAlpacaHttpException (HttpExceptionRequest _ exceptionContent) =
  case exceptionContent of
    ResponseTimeout ->
      FailureDetail
        { reasonCode = DataSourceTimeout
        , detail = Just "Alpaca HTTP response timeout"
        , retryable = True
        }
    ConnectionTimeout ->
      FailureDetail
        { reasonCode = DataSourceTimeout
        , detail = Just "Alpaca HTTP connection timeout"
        , retryable = True
        }
    ConnectionFailure cause ->
      FailureDetail
        { reasonCode = DataSourceUnavailable
        , detail = Just ("Alpaca connection failure: " <> Text.pack (show cause))
        , retryable = True
        }
    other ->
      FailureDetail
        { reasonCode = DataSourceUnavailable
        , detail = Just ("Alpaca HTTP exception: " <> Text.pack (show other))
        , retryable = True
        }
mapAlpacaHttpException (InvalidUrlException url reason) =
  FailureDetail
    { reasonCode = DataSchemaInvalid
    , detail = Just ("Invalid Alpaca URL " <> Text.pack url <> ": " <> Text.pack reason)
    , retryable = False
    }
