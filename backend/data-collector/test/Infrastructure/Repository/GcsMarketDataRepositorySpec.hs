module Infrastructure.Repository.GcsMarketDataRepositorySpec (spec) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.MarketCollection.Aggregate (MarketCollectionIdentifier (..))
import Domain.MarketCollection.CollectionQualityPolicy (RawMarketField (..), RawMarketRecord (..))
import Infrastructure.Repository.GcsMarketDataRepository (
  GcsMarketDataEnv (..),
  runGcsMarketDataRepositoryT,
 )
import Storage.GCS (GcsObjectRef (..), defaultGcsContext)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.CollectMarketData (NormalizedMarketDataset (..), RawMarketDataPort (..))

spec :: Spec
spec = do
  describe "GcsMarketDataRepositoryT" $ do
    -- TC-INFRA-001
    describe "TC-INFRA-001: persistRawMarketData" $ do
      it "returns Right storagePath and writes NDJSON with §8.4 fields" $ do
        writtenRef <- newIORef (Nothing :: Maybe (GcsObjectRef, ByteString.Lazy.ByteString))
        let fakeFn objectRef _contentType body = do
              writeIORef writtenRef (Just (objectRef, body))
              pure (Right ())
            environment =
              GcsMarketDataEnv
                { gcsContext = defaultGcsContext
                , bucketName = "test-bucket"
                , uploadFn = fakeFn
                }
            collectionIdentifier = MarketCollectionIdentifier{value = testUlid}
            targetDay = fromGregorian 2026 1 15
            dataset =
              NormalizedMarketDataset
                { records = [makeJQuantsRecord "1306.T" "2026-01-15"]
                , rowCount = 1
                }
        result <-
          runGcsMarketDataRepositoryT environment $
            persistRawMarketData collectionIdentifier targetDay dataset
        case result of
          Left uploadError -> fail ("expected Right, got Left: " <> Text.unpack uploadError)
          Right storagePath -> do
            -- Check storagePath format
            storagePath `shouldSatisfy` Text.isInfixOf "normalized_market_data/date=2026-01-15"
            storagePath `shouldSatisfy` Text.isInfixOf "market_snapshot.ndjson"
            -- Check written bytes
            maybeWritten <- readIORef writtenRef
            case maybeWritten of
              Nothing -> fail "uploadFn was not called"
              Just (objectRef, body) -> do
                objectRef.bucket `shouldBe` "test-bucket"
                objectRef.objectPath `shouldSatisfy` Text.isInfixOf "date=2026-01-15"
                -- Decode first NDJSON line
                let allLines = ByteString.Lazy.split 0x0A body
                let firstLine = case allLines of
                      [] -> ByteString.Lazy.empty
                      (line : _) -> line
                case Aeson.decode firstLine :: Maybe Aeson.Value of
                  Nothing -> fail "could not decode NDJSON line as JSON"
                  Just (Aeson.Object jsonObject) -> do
                    -- §8.4 fields
                    let hasField k = isJust (KeyMap.lookup k jsonObject)
                    hasField "identifier" `shouldBe` True
                    hasField "targetDate" `shouldBe` True
                    hasField "symbol" `shouldBe` True
                    hasField "open" `shouldBe` True
                    hasField "openRaw" `shouldBe` True
                    hasField "adjustmentCumFactor" `shouldBe` True
                    hasField "source" `shouldBe` True
                    hasField "collectedAt" `shouldBe` True
                    hasField "trace" `shouldBe` True
                  Just other -> fail ("expected JSON object, got: " <> show other)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 1 of
  Right ulid -> ulid
  Left _ -> error "test ulid"

makeJQuantsRecord :: Text -> Text -> RawMarketRecord
makeJQuantsRecord symbol date =
  RawMarketRecord
    { fields =
        [ ("Code", FieldText symbol)
        , ("Date", FieldText date)
        , ("AdjustmentFactor", FieldDouble 1.0)
        , ("Open", FieldDouble 1000.0)
        , ("High", FieldDouble 1010.0)
        , ("Low", FieldDouble 990.0)
        , ("Close", FieldDouble 1005.0)
        , ("Volume", FieldDouble 10000.0)
        , ("Source", FieldText "jquants")
        ]
    }
