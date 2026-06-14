module Infrastructure.ACL.NisshokinCsvSourceAdapterSpec (spec) where

import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time (Day)
import Data.Time.Calendar (fromGregorian)
import Domain.MarketCollection.Aggregate (FailureDetail (..))
import Domain.MarketCollection.CollectionQualityPolicy (RawMarketField (..), RawMarketRecord (..))
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Infrastructure.ACL.NisshokinCsvSourceAdapter (
  NisshokinEnv (..),
  fetchNisshokinCsvData,
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

buildTextResponse :: Int -> Text -> Response ByteString.Lazy.ByteString
buildTextResponse statusCodeValue body =
  Response
    { responseStatus = if statusCodeValue >= 500 then status503 else status200
    , responseVersion = http11
    , responseHeaders = []
    , responseBody = ByteString.Lazy.fromStrict (Text.Encoding.encodeUtf8 body)
    , responseCookieJar = CJ []
    , responseClose' = ResponseClose (pure ())
    , responseOriginalRequest = defaultRequest
    , responseEarlyHints = []
    }

-- | Valid Nisshokin CSV with all required columns
validCsvFixture :: Text
validCsvFixture =
  Text.unlines
    [ "銘柄コード,対象日,品貸料,その他"
    , "1306,2025-06-01,0.5,extra"
    , "1321,2025-06-01,0.3,extra"
    ]

-- | CSV missing 品貸料 column (TC-ACL-010)
missingColumnCsvFixture :: Text
missingColumnCsvFixture =
  Text.unlines
    [ "銘柄コード,対象日,違う列"
    , "1306,2025-06-01,xxx"
    ]

-- ---------------------------------------------------------------------------
-- Env builders
-- ---------------------------------------------------------------------------

makeEnvWithHttp ::
  (Request -> IO (Response ByteString.Lazy.ByteString)) ->
  NisshokinEnv
makeEnvWithHttp fakeHttp =
  NisshokinEnv
    { timeoutSeconds = 60
    , httpExecute = fakeHttp
    , browserFallback = \_ -> pure (Right [])
    , onBrowserFallback = \_ -> pure ()
    }

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
  describe "Infrastructure.ACL.NisshokinCsvSourceAdapter" $ do
    -- TC-ACL-008: Valid CSV → Right [RawMarketRecord]
    describe "TC-ACL-008: 有効CSV → Right [RawMarketRecord] (Must-03, Must-13)" $ do
      it "returns Right with 銘柄コード, 対象日, 品貸料 fields" $ do
        let fakeHttp _ = pure (buildTextResponse 200 validCsvFixture)
        let environment = makeEnvWithHttp fakeHttp
        result <- fetchNisshokinCsvData environment testDay
        case result of
          Left failure -> fail ("Expected Right, got Left: " <> show failure)
          Right [] -> fail "Expected non-empty records"
          Right (firstRecord : _) -> do
            hasField "銘柄コード" firstRecord `shouldBe` True
            hasField "対象日" firstRecord `shouldBe` True
            hasField "品貸料" firstRecord `shouldBe` True

      it "returns 2 records for 2 data rows" $ do
        let fakeHttp _ = pure (buildTextResponse 200 validCsvFixture)
        let environment = makeEnvWithHttp fakeHttp
        result <- fetchNisshokinCsvData environment testDay
        case result of
          Left failure -> fail ("Expected Right, got Left: " <> show failure)
          Right records -> length records `shouldBe` 2

    -- TC-ACL-009: URL direct 2 failures → browserFallback invoked
    describe "TC-ACL-009: URL直接2回失敗 → browserFallback 切替 (Must-12)" $ do
      it "invokes browserFallback after 2 direct HTTP failures" $ do
        fallbackCalledRef <- newIORef False
        onBrowserFallbackCalledRef <- newIORef (0 :: Int)
        -- URL direct always returns 503
        let failingHttp _ = pure (buildTextResponse 503 "server error")
        -- browserFallback records invocation
        let trackingFallback _ = do
              modifyIORef' fallbackCalledRef (const True)
              pure (Right [])
        let environment =
              NisshokinEnv
                { timeoutSeconds = 60
                , httpExecute = failingHttp
                , browserFallback = trackingFallback
                , onBrowserFallback = \_ ->
                    modifyIORef' onBrowserFallbackCalledRef (+ 1)
                }
        _ <- fetchNisshokinCsvData environment testDay
        -- browserFallback should have been called
        fallbackCalled <- readIORef fallbackCalledRef
        fallbackCalled `shouldBe` True
        -- Must-14: onBrowserFallback capability should have been called once
        onBrowserFallbackCount <- readIORef onBrowserFallbackCalledRef
        onBrowserFallbackCount `shouldBe` 1

      it "returns browserFallback result when URL direct fails twice" $ do
        let fallbackRecord =
              RawMarketRecord
                { fields =
                    [ ("銘柄コード", FieldText "1306")
                    , ("対象日", FieldText "2025-06-01")
                    , ("品貸料", FieldText "0.5")
                    ]
                }
        let failingHttp _ = pure (buildTextResponse 503 "server error")
        let successFallback _ = pure (Right [fallbackRecord])
        let environment =
              NisshokinEnv
                { timeoutSeconds = 60
                , httpExecute = failingHttp
                , browserFallback = successFallback
                , onBrowserFallback = \_ -> pure ()
                }
        result <- fetchNisshokinCsvData environment testDay
        result `shouldBe` Right [fallbackRecord]

      it "returns DataSourceUnavailable when all 3 attempts fail" $ do
        let failingHttp _ = pure (buildTextResponse 503 "server error")
        let failingFallback _ =
              pure
                ( Left
                    FailureDetail
                      { reasonCode = DataSourceUnavailable
                      , detail = Just "browser fallback failed"
                      , retryable = True
                      }
                )
        let environment =
              NisshokinEnv
                { timeoutSeconds = 60
                , httpExecute = failingHttp
                , browserFallback = failingFallback
                , onBrowserFallback = \_ -> pure ()
                }
        result <- fetchNisshokinCsvData environment testDay
        case result of
          Right _ -> fail "Expected Left, got Right"
          Left failure -> failure.reasonCode `shouldBe` DataSourceUnavailable

    -- TC-ACL-010: Missing required column → Left DataSchemaInvalid
    describe "TC-ACL-010: 必須列欠損 → Left DataSchemaInvalid (Must-13)" $ do
      it "returns Left DataSchemaInvalid when 品貸料 column is missing" $ do
        let fakeHttp _ = pure (buildTextResponse 200 missingColumnCsvFixture)
        let environment = makeEnvWithHttp fakeHttp
        result <- fetchNisshokinCsvData environment testDay
        case result of
          Right _ -> fail "Expected Left, got Right"
          Left failure -> do
            failure.reasonCode `shouldBe` DataSchemaInvalid
            failure.retryable `shouldBe` False

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

hasField :: Text -> RawMarketRecord -> Bool
hasField fieldName record = any ((== fieldName) . fst) record.fields
