module Infrastructure.ACL.AlpacaMarketDataSourceTSpec (spec) where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Time (Day)
import Data.Time.Calendar (fromGregorian)
import Domain.MarketCollection.CollectionQualityPolicy (RawMarketRecord (..))
import Domain.MarketCollection.MarketDataSource (MarketDataSource (..))
import Infrastructure.ACL.AlpacaMarketDataSourceT (
  AlpacaEnv (..),
  runAlpacaMarketDataSourceT,
 )
import Network.HTTP.Client (
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

-- | AlpacaEnv with usCollectionEnabled=False (Must-09 MVP default)
makeDisabledEnv :: AlpacaEnv
makeDisabledEnv =
  AlpacaEnv
    { usCollectionEnabled = False
    , apiKeyIdentifier = "test-key-id"
    , apiSecretKey = "test-secret"
    , timeoutSeconds = 30
    , baseUrl = "https://data.alpaca.markets/v2"
    , httpExecute = \_ -> error "httpExecute must not be called when usCollectionEnabled=False"
    }

makeEnabledEnv :: (Request -> IO (Response ByteString.Lazy.ByteString)) -> AlpacaEnv
makeEnabledEnv fakeHttp =
  AlpacaEnv
    { usCollectionEnabled = True
    , apiKeyIdentifier = "test-key-id"
    , apiSecretKey = "test-secret"
    , timeoutSeconds = 30
    , baseUrl = "https://data.alpaca.markets/v2"
    , httpExecute = fakeHttp
    }

-- ---------------------------------------------------------------------------
-- Alpaca bars fixture — TC-ACL-007
-- ---------------------------------------------------------------------------

barsFixture :: Aeson.Value
barsFixture =
  Aeson.object
    [ "bars"
        Aeson..= Aeson.object
          [ "AAPL"
              Aeson..= Aeson.toJSONList
                [ Aeson.object
                    [ "t" Aeson..= ("2025-06-01T00:00:00Z" :: Text)
                    , "o" Aeson..= (150.0 :: Double)
                    , "h" Aeson..= (155.0 :: Double)
                    , "l" Aeson..= (149.0 :: Double)
                    , "c" Aeson..= (153.0 :: Double)
                    , "v" Aeson..= (1000000.0 :: Double)
                    , "vw" Aeson..= (152.5 :: Double)
                    , "n" Aeson..= (5000 :: Int)
                    ]
                ]
          ]
    ]

barsPage1Fixture :: Aeson.Value
barsPage1Fixture =
  Aeson.object
    [ "bars"
        Aeson..= Aeson.object
          [ "AAPL"
              Aeson..= Aeson.toJSONList
                [ Aeson.object
                    [ "t" Aeson..= ("2025-06-01T00:00:00Z" :: Text)
                    , "o" Aeson..= (150.0 :: Double)
                    , "h" Aeson..= (155.0 :: Double)
                    , "l" Aeson..= (149.0 :: Double)
                    , "c" Aeson..= (153.0 :: Double)
                    , "v" Aeson..= (1000000.0 :: Double)
                    ]
                ]
          ]
    , "next_page_token" Aeson..= ("token123" :: Text)
    ]

barsPage2Fixture :: Aeson.Value
barsPage2Fixture =
  Aeson.object
    [ "bars"
        Aeson..= Aeson.object
          [ "MSFT"
              Aeson..= Aeson.toJSONList
                [ Aeson.object
                    [ "t" Aeson..= ("2025-06-01T00:00:00Z" :: Text)
                    , "o" Aeson..= (300.0 :: Double)
                    , "h" Aeson..= (310.0 :: Double)
                    , "l" Aeson..= (295.0 :: Double)
                    , "c" Aeson..= (305.0 :: Double)
                    , "v" Aeson..= (500000.0 :: Double)
                    ]
                ]
          ]
    ]

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
  describe "Infrastructure.ACL.AlpacaMarketDataSourceT" $ do
    -- TC-ACL-006: usCollectionEnabled=False → Right [] no HTTP calls
    describe "TC-ACL-006: usCollectionEnabled=False → Right [] (Must-09)" $ do
      it "returns Right [] without making any HTTP requests" $ do
        callCountRef <- newIORef (0 :: Int)
        -- httpExecute should never be called
        let countingHttp _ = do
              modifyIORef' callCountRef (+ 1)
              pure (buildJsonResponse 200 (Aeson.object []))
        let environment = makeDisabledEnv{httpExecute = countingHttp}
        result <- runAlpacaMarketDataSourceT environment (fetchUsMarketData testDay)
        result `shouldBe` Right []
        callCount <- readIORef callCountRef
        callCount `shouldBe` 0

    -- TC-ACL-007: usCollectionEnabled=True → Right [RawMarketRecord] with t,o,h,l,c,v fields
    describe "TC-ACL-007: usCollectionEnabled=True → Right [RawMarketRecord] (Must-10, Must-11)" $ do
      it "returns Right with t, o, h, l, c, v fields present" $ do
        let fakeHttp _ = pure (buildJsonResponse 200 barsFixture)
        let environment = makeEnabledEnv fakeHttp
        result <- runAlpacaMarketDataSourceT environment (fetchUsMarketData testDay)
        case result of
          Left failure -> fail ("Expected Right, got Left: " <> show failure)
          Right [] -> fail "Expected non-empty records"
          Right (firstRecord : _) -> do
            hasField "t" firstRecord `shouldBe` True
            hasField "o" firstRecord `shouldBe` True
            hasField "h" firstRecord `shouldBe` True
            hasField "l" firstRecord `shouldBe` True
            hasField "c" firstRecord `shouldBe` True
            hasField "v" firstRecord `shouldBe` True

      it "includes vw field when present" $ do
        let fakeHttp _ = pure (buildJsonResponse 200 barsFixture)
        let environment = makeEnabledEnv fakeHttp
        result <- runAlpacaMarketDataSourceT environment (fetchUsMarketData testDay)
        case result of
          Left failure -> fail ("Expected Right, got Left: " <> show failure)
          Right [] -> fail "Expected non-empty records"
          Right (firstRecord : _) -> hasField "vw" firstRecord `shouldBe` True

      it "includes n field when present" $ do
        let fakeHttp _ = pure (buildJsonResponse 200 barsFixture)
        let environment = makeEnabledEnv fakeHttp
        result <- runAlpacaMarketDataSourceT environment (fetchUsMarketData testDay)
        case result of
          Left failure -> fail ("Expected Right, got Left: " <> show failure)
          Right [] -> fail "Expected non-empty records"
          Right (firstRecord : _) -> hasField "n" firstRecord `shouldBe` True

    -- TC-ACL-007: next_page_token pagination
    describe "TC-ACL-007: next_page_token ページング (Must-10)" $ do
      it "follows next_page_token and merges AAPL and MSFT bars" $ do
        counterRef <- newIORef (0 :: Int)
        let responses = [barsPage1Fixture, barsPage2Fixture]
        let fakeHttp = makeCountingFakeHttp counterRef responses
        let environment = makeEnabledEnv fakeHttp
        result <- runAlpacaMarketDataSourceT environment (fetchUsMarketData testDay)
        case result of
          Left failure -> fail ("Expected Right, got Left: " <> show failure)
          Right records -> do
            -- Both AAPL and MSFT bars should be present
            null records `shouldBe` False
            (length records >= 2) `shouldBe` True

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

hasField :: Text -> RawMarketRecord -> Bool
hasField fieldName record = any ((== fieldName) . fst) record.fields
