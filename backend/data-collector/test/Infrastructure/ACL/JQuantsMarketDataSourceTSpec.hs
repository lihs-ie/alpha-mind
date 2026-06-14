module Infrastructure.ACL.JQuantsMarketDataSourceTSpec (spec) where

import Control.Exception (throwIO)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time (Day)
import Data.Time.Calendar (fromGregorian)
import Domain.MarketCollection.Aggregate (FailureDetail (..))
import Domain.MarketCollection.CollectionQualityPolicy (RawMarketField (..), RawMarketRecord (..))
import Domain.MarketCollection.MarketDataSource (MarketDataSource (..))
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Infrastructure.ACL.JQuantsMarketDataSourceT (
  JQuantsEnv (..),
  isRetryableForAcl,
  runJQuantsMarketDataSourceT,
 )
import Infrastructure.ACL.NisshokinCsvSourceAdapter (NisshokinEnv (..))
import Network.HTTP.Client (
  HttpException (..),
  HttpExceptionContent (..),
  Request,
  Response,
  defaultRequest,
 )
import Network.HTTP.Client.Internal (CookieJar (..), Response (..), ResponseClose (..))
import Network.HTTP.Types (http11, status200, status503)
import Test.Hspec (Spec, describe, it, shouldBe)

-- ---------------------------------------------------------------------------
-- Test fixtures
-- ---------------------------------------------------------------------------

testDay :: Day
testDay = fromGregorian 2025 6 1

-- | Build a fake HTTP response from a JSON Value.
buildJsonResponse :: Int -> Aeson.Value -> Response ByteString.Lazy.ByteString
buildJsonResponse statusCodeValue body =
  Response
    { responseStatus = if statusCodeValue >= 500 then status503 else status200
    , responseVersion = http11
    , responseHeaders = []
    , responseBody = Aeson.encode body
    , responseCookieJar = CJ []
    , responseClose' = ResponseClose (pure ())
    , responseOriginalRequest = defaultRequest
    , responseEarlyHints = []
    }

-- | Fake httpExecute that cycles through a list of responses by IORef counter
makeCountingFakeHttp ::
  IORef Int ->
  [Aeson.Value] ->
  Request ->
  IO (Response ByteString.Lazy.ByteString)
makeCountingFakeHttp counterRef responses _ = do
  count <- readIORef counterRef
  modifyIORef' counterRef (+ 1)
  let body = case drop count responses of
        [] -> Aeson.object []
        (b : _) -> b
  pure (buildJsonResponse 200 body)

{- | Minimal NisshokinEnv that returns empty success (J-Quants tests don't need it)
Must-03: In J-Quants tests, Nisshokin is called internally but we return empty
to avoid coupling — the browserFallback returns Right [] so Nisshokin succeeds trivially.
-}
fakeNisshokinEnvSuccess :: NisshokinEnv
fakeNisshokinEnvSuccess =
  NisshokinEnv
    { timeoutSeconds = 60
    , httpExecute = \_ ->
        pure
          (buildCsvResponse 200 "銘柄コード,対象日,品貸料\n")
    , browserFallback = \_ -> pure (Right [])
    , onBrowserFallback = \_ -> pure ()
    }

-- | Build a fake HTTP CSV response
buildCsvResponse :: Int -> Text -> Response ByteString.Lazy.ByteString
buildCsvResponse statusCodeValue body =
  ( Response
      { responseStatus = if statusCodeValue >= 500 then status503 else status200
      , responseVersion = http11
      , responseHeaders = []
      , responseBody = ByteString.Lazy.fromStrict (Text.Encoding.encodeUtf8 body)
      , responseCookieJar = CJ []
      , responseClose' = ResponseClose (pure ())
      , responseOriginalRequest = defaultRequest
      , responseEarlyHints = []
      } ::
      Response ByteString.Lazy.ByteString
  )

makeEnv ::
  (Request -> IO (Response ByteString.Lazy.ByteString)) ->
  JQuantsEnv
makeEnv fakeHttp =
  JQuantsEnv
    { baseUrl = "https://api.jquants-pro.com/v2"
    , idToken = "test-token"
    , timeoutSeconds = 30
    , httpExecute = fakeHttp
    , nisshokinEnv = fakeNisshokinEnvSuccess
    }

-- ---------------------------------------------------------------------------
-- Fixture JSON values
-- ---------------------------------------------------------------------------

listedInfoFixture :: Aeson.Value
listedInfoFixture =
  Aeson.object
    [ "info"
        Aeson..= Aeson.toJSONList
          [ Aeson.object
              [ "Date" Aeson..= ("2025-06-01" :: Text)
              , "Code" Aeson..= ("1306" :: Text)
              , "MarketCode" Aeson..= ("0111" :: Text)
              , "MarketCodeName" Aeson..= ("プライム" :: Text)
              , "Sector17Code" Aeson..= ("16" :: Text)
              , "Sector33Code" Aeson..= ("5108" :: Text)
              , "ScaleCategory" Aeson..= ("TOPIX Large70" :: Text)
              , "MarginCode" Aeson..= ("1" :: Text)
              ]
          ]
    ]

dailyQuotesFixture :: Aeson.Value
dailyQuotesFixture =
  Aeson.object
    [ "daily_quotes"
        Aeson..= Aeson.toJSONList
          [ Aeson.object
              [ "Date" Aeson..= ("2025-06-01" :: Text)
              , "Code" Aeson..= ("1306" :: Text)
              , "Open" Aeson..= (2000.0 :: Double)
              , "High" Aeson..= (2050.0 :: Double)
              , "Low" Aeson..= (1990.0 :: Double)
              , "Close" Aeson..= (2030.0 :: Double)
              , "Volume" Aeson..= (500000.0 :: Double)
              , "TurnoverValue" Aeson..= (1000000000.0 :: Double)
              , "AdjustmentFactor" Aeson..= (1.0 :: Double)
              , "AdjustmentOpen" Aeson..= (2000.0 :: Double)
              , "AdjustmentHigh" Aeson..= (2050.0 :: Double)
              , "AdjustmentLow" Aeson..= (1990.0 :: Double)
              , "AdjustmentClose" Aeson..= (2030.0 :: Double)
              , "AdjustmentVolume" Aeson..= (500000.0 :: Double)
              ]
          ]
    ]

dailyQuotesAdjustmentFactorZero :: Aeson.Value
dailyQuotesAdjustmentFactorZero =
  Aeson.object
    [ "daily_quotes"
        Aeson..= Aeson.toJSONList
          [ Aeson.object
              [ "Date" Aeson..= ("2025-06-01" :: Text)
              , "Code" Aeson..= ("1306" :: Text)
              , "Open" Aeson..= (2000.0 :: Double)
              , "High" Aeson..= (2050.0 :: Double)
              , "Low" Aeson..= (1990.0 :: Double)
              , "Close" Aeson..= (2030.0 :: Double)
              , "Volume" Aeson..= (500000.0 :: Double)
              , "TurnoverValue" Aeson..= (1000000000.0 :: Double)
              , "AdjustmentFactor" Aeson..= (0.0 :: Double)
              , "AdjustmentOpen" Aeson..= (2000.0 :: Double)
              , "AdjustmentHigh" Aeson..= (2050.0 :: Double)
              , "AdjustmentLow" Aeson..= (1990.0 :: Double)
              , "AdjustmentClose" Aeson..= (2030.0 :: Double)
              , "AdjustmentVolume" Aeson..= (500000.0 :: Double)
              ]
          ]
    ]

dailyQuotesPage1 :: Aeson.Value
dailyQuotesPage1 =
  Aeson.object
    [ "daily_quotes"
        Aeson..= Aeson.toJSONList
          [ Aeson.object
              [ "Date" Aeson..= ("2025-06-01" :: Text)
              , "Code" Aeson..= ("1306" :: Text)
              , "Open" Aeson..= (2000.0 :: Double)
              , "High" Aeson..= (2050.0 :: Double)
              , "Low" Aeson..= (1990.0 :: Double)
              , "Close" Aeson..= (2030.0 :: Double)
              , "Volume" Aeson..= (500000.0 :: Double)
              , "TurnoverValue" Aeson..= (1000000000.0 :: Double)
              , "AdjustmentFactor" Aeson..= (1.0 :: Double)
              , "AdjustmentOpen" Aeson..= (2000.0 :: Double)
              , "AdjustmentHigh" Aeson..= (2050.0 :: Double)
              , "AdjustmentLow" Aeson..= (1990.0 :: Double)
              , "AdjustmentClose" Aeson..= (2030.0 :: Double)
              , "AdjustmentVolume" Aeson..= (500000.0 :: Double)
              ]
          ]
    , "pagination_key" Aeson..= ("page2key" :: Text)
    ]

dailyQuotesPage2 :: Aeson.Value
dailyQuotesPage2 =
  Aeson.object
    [ "daily_quotes"
        Aeson..= Aeson.toJSONList
          [ Aeson.object
              [ "Date" Aeson..= ("2025-06-01" :: Text)
              , "Code" Aeson..= ("1321" :: Text)
              , "Open" Aeson..= (3000.0 :: Double)
              , "High" Aeson..= (3100.0 :: Double)
              , "Low" Aeson..= (2950.0 :: Double)
              , "Close" Aeson..= (3050.0 :: Double)
              , "Volume" Aeson..= (200000.0 :: Double)
              , "TurnoverValue" Aeson..= (600000000.0 :: Double)
              , "AdjustmentFactor" Aeson..= (1.0 :: Double)
              , "AdjustmentOpen" Aeson..= (3000.0 :: Double)
              , "AdjustmentHigh" Aeson..= (3100.0 :: Double)
              , "AdjustmentLow" Aeson..= (2950.0 :: Double)
              , "AdjustmentClose" Aeson..= (3050.0 :: Double)
              , "AdjustmentVolume" Aeson..= (200000.0 :: Double)
              ]
          ]
    ]

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
  describe "Infrastructure.ACL.JQuantsMarketDataSourceT" $ do
    -- TC-ACL-001: Normal fetch → Right [RawMarketRecord] with Must-06 fields
    describe "TC-ACL-001: 正常フィクスチャ → Right [RawMarketRecord] (Must-06 columns)" $ do
      it "returns Right with Date, Code, Open, AdjustmentFactor fields present" $ do
        counterRef <- newIORef (0 :: Int)
        let responses = [listedInfoFixture, dailyQuotesFixture]
        let fakeHttp = makeCountingFakeHttp counterRef responses
        let environment = makeEnv fakeHttp
        result <- runJQuantsMarketDataSourceT environment (fetchJapanMarketData testDay)
        case result of
          Left failure -> fail ("Expected Right, got Left: " <> show failure)
          Right records -> do
            -- At least one record from daily_quotes has the required fields
            let quoteRecords = filter (hasField "AdjustmentFactor") records
            null quoteRecords `shouldBe` False
            case quoteRecords of
              [] -> fail "Expected non-empty quote records"
              (firstQuote : _) -> do
                hasField "Date" firstQuote `shouldBe` True
                hasField "Code" firstQuote `shouldBe` True
                hasField "Open" firstQuote `shouldBe` True
                hasField "AdjustmentFactor" firstQuote `shouldBe` True
                -- Must-08: raw values only, no adjusted price recalculation
                hasField "Close" firstQuote `shouldBe` True
                getDoubleField "Open" firstQuote `shouldBe` Just 2000.0

    -- TC-ACL-002: AdjustmentFactor=0 → Left DataSchemaInvalid
    describe "TC-ACL-002: AdjustmentFactor=0 → Left DataSchemaInvalid (Must-07)" $ do
      it "returns Left with reasonCode=DataSchemaInvalid and retryable=False" $ do
        counterRef <- newIORef (0 :: Int)
        let responses = [listedInfoFixture, dailyQuotesAdjustmentFactorZero]
        let fakeHttp = makeCountingFakeHttp counterRef responses
        let environment = makeEnv fakeHttp
        result <- runJQuantsMarketDataSourceT environment (fetchJapanMarketData testDay)
        case result of
          Right _ -> fail "Expected Left, got Right"
          Left failure -> do
            failure.reasonCode `shouldBe` DataSchemaInvalid
            failure.retryable `shouldBe` False

    -- TC-ACL-003: pagination_key → 2 requests, results merged
    describe "TC-ACL-003: pagination_key あり → ページング取得 (Must-05)" $ do
      it "fetches both pages and merges records from 1306 and 1321" $ do
        counterRef <- newIORef (0 :: Int)
        -- listed/info(0), daily_quotes page1 with key(1), daily_quotes page2(2)
        let responses = [listedInfoFixture, dailyQuotesPage1, dailyQuotesPage2]
        let fakeHttp = makeCountingFakeHttp counterRef responses
        let environment = makeEnv fakeHttp
        result <- runJQuantsMarketDataSourceT environment (fetchJapanMarketData testDay)
        case result of
          Left failure -> fail ("Expected Right, got Left: " <> show failure)
          Right records -> do
            let codes = [v | record <- records, ("Code", FieldText v) <- record.fields]
            ("1306" `elem` codes) `shouldBe` True
            ("1321" `elem` codes) `shouldBe` True
        callCount <- readIORef counterRef
        -- At minimum: listed/info + page1 + page2 = 3 calls
        (callCount >= 3) `shouldBe` True

    -- TC-ACL-004: Timeout → Left DataSourceTimeout retryable=True
    describe "TC-ACL-004: タイムアウト → Left DataSourceTimeout retryable=True (Must-17)" $ do
      it "returns Left DataSourceTimeout with retryable=True on ResponseTimeout" $ do
        let fakeHttp _ = throwIO (HttpExceptionRequest defaultRequest ResponseTimeout)
        let environment = makeEnv fakeHttp
        result <- runJQuantsMarketDataSourceT environment (fetchJapanMarketData testDay)
        case result of
          Right _ -> fail "Expected Left, got Right"
          Left failure -> do
            failure.reasonCode `shouldBe` DataSourceTimeout
            failure.retryable `shouldBe` True

    -- TC-ACL-005: 5xx → Left DataSourceUnavailable retryable=True
    describe "TC-ACL-005: 5xx → Left DataSourceUnavailable retryable=True (Must-18)" $ do
      it "returns Left DataSourceUnavailable with retryable=True on HTTP 503" $ do
        let fakeHttp _ = pure (buildJsonResponse 503 (Aeson.object []))
        let environment = makeEnv fakeHttp
        result <- runJQuantsMarketDataSourceT environment (fetchJapanMarketData testDay)
        case result of
          Right _ -> fail "Expected Left, got Right"
          Left failure -> do
            failure.reasonCode `shouldBe` DataSourceUnavailable
            failure.retryable `shouldBe` True

    -- TC-ACL-011: isRetryableForAcl predicate
    describe "TC-ACL-011: isRetryableForAcl 述語 (Must-16)" $ do
      it "returns True for DataSourceTimeout with retryable=True" $ do
        let timeoutFailure =
              FailureDetail
                { reasonCode = DataSourceTimeout
                , detail = Just "timeout"
                , retryable = True
                }
        isRetryableForAcl timeoutFailure `shouldBe` True

      it "returns False for DataSchemaInvalid with retryable=False" $ do
        let parseFailure =
              FailureDetail
                { reasonCode = DataSchemaInvalid
                , detail = Just "parse error"
                , retryable = False
                }
        isRetryableForAcl parseFailure `shouldBe` False

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

hasField :: Text -> RawMarketRecord -> Bool
hasField fieldName record = any ((== fieldName) . fst) record.fields

getDoubleField :: Text -> RawMarketRecord -> Maybe Double
getDoubleField fieldName record =
  case lookup fieldName record.fields of
    Just (FieldDouble value) -> Just value
    _ -> Nothing
