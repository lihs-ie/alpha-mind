module Infrastructure.Normalization.MarketDataNormalizerSpec (spec) where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (Day, UTCTime (..), fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.MarketCollection.CollectionQualityPolicy (RawMarketField (..), RawMarketRecord (..))
import Infrastructure.Normalization.MarketDataNormalizer (
  normalize,
  normalizedRecordAdjustmentBaseDate,
  normalizedRecordAdjustmentCumFactor,
  normalizedRecordOpen,
  normalizedRecordReverseLoanFee,
  normalizedRecordSymbol,
  normalizedRecordTargetDate,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
  describe "MarketDataNormalizer" $ do
    -- TC-INFRA-003: AdjustmentFactor <= 0 -> Left
    describe "TC-INFRA-003: AdjustmentFactor <= 0" $ do
      it "returns Left when AdjustmentFactor is zero" $ do
        let records = [makeJQuantsRecord "1306.T" "2026-01-15" 0.0 1000.0 1010.0 990.0 1005.0 10000.0]
        let result = normalize testUlid testDate testTime testUlid records
        case result of
          Left message -> message `shouldSatisfy` Text.isInfixOf "DATA_SCHEMA_INVALID"
          Right _ -> fail "expected Left for AdjustmentFactor = 0"

      it "returns Left when AdjustmentFactor is negative" $ do
        let records = [makeJQuantsRecord "1306.T" "2026-01-15" (-0.5) 1000.0 1010.0 990.0 1005.0 10000.0]
        let result = normalize testUlid testDate testTime testUlid records
        case result of
          Left message -> message `shouldSatisfy` Text.isInfixOf "DATA_SCHEMA_INVALID"
          Right _ -> fail "expected Left for AdjustmentFactor < 0"

    -- TC-INFRA-002: cumprod + shift adjustment
    describe "TC-INFRA-002: cumprod adjustment" $ do
      it "applies cumFactor = [1.0, 1.0, 0.5] after shift for AdjustmentFactor = [1.0, 0.5, 1.0] descending" $ do
        -- AdjustmentFactor descending order (newest first) = [1.0, 0.5, 1.0]
        -- cumFactor (scan) = [1.0, 0.5, 0.5]
        -- shifted = [1.0, 1.0, 0.5]  (head = 1.0, tail = init of cumFactors)
        -- adjusted open for oldest record (2026-01-15) = 1500 * 0.5 = 750
        let records =
              [ makeJQuantsRecord "1306.T" "2026-01-17" 1.0 1000.0 1010.0 990.0 1005.0 10000.0
              , makeJQuantsRecord "1306.T" "2026-01-16" 0.5 2000.0 2020.0 1980.0 2010.0 5000.0
              , makeJQuantsRecord "1306.T" "2026-01-15" 1.0 1500.0 1520.0 1480.0 1510.0 8000.0
              ]
        let result = normalize testUlid testDate testTime testUlid records
        case result of
          Left normalizationError -> fail ("unexpected Left: " <> show normalizationError)
          Right normalized -> do
            length normalized `shouldBe` 3
            let findByDate d = filter (\r -> show (normalizedRecordTargetDate r) == d) normalized
            case findByDate "2026-01-15" of
              [] -> fail "no record for 2026-01-15"
              (record : _) -> do
                -- adjustmentCumFactor should be 0.5
                normalizedRecordAdjustmentCumFactor record `shouldSatisfy` (\f -> abs (f - 0.5) < 1e-9)
                -- open_adj = 1500 * 0.5 = 750
                normalizedRecordOpen record `shouldSatisfy` (\f -> abs (f - 750.0) < 1e-9)
            case findByDate "2026-01-17" of
              [] -> fail "no record for 2026-01-17"
              (record : _) -> do
                normalizedRecordAdjustmentCumFactor record `shouldSatisfy` (\f -> abs (f - 1.0) < 1e-9)
                normalizedRecordOpen record `shouldSatisfy` (\f -> abs (f - 1000.0) < 1e-9)

    -- Must-09: adjustmentBaseDate = targetDate (collection target date, not record date)
    describe "Must-09: adjustmentBaseDate equals collection targetDate" $ do
      it "adjustmentBaseDate is set to the collection targetDate, not the individual record date" $ do
        -- The collection targetDate is 2026-01-20 (the day we ran the collection)
        -- but the records are for 2026-01-15 through 2026-01-17 (historical data)
        let collectionDay = fromGregorian 2026 1 20
            records = [makeJQuantsRecord "1306.T" "2026-01-15" 1.0 1000.0 1010.0 990.0 1005.0 10000.0]
        let result = normalize testUlid collectionDay testTime testUlid records
        case result of
          Left normalizationError -> fail ("unexpected Left: " <> show normalizationError)
          Right normalized ->
            case normalized of
              [] -> fail "expected at least one record"
              (record : _) ->
                -- adjustmentBaseDate must equal the collection targetDate (2026-01-20),
                -- not the individual record date (2026-01-15)
                normalizedRecordAdjustmentBaseDate record `shouldBe` collectionDay

    -- TC-INFRA-008: reverseLoanFee inner join
    describe "TC-INFRA-008: reverseLoanFee join" $ do
      it "fills reverseLoanFee when nisshokin record matches symbol and date" $ do
        let jquantsRecord = makeJQuantsRecord "1306.T" "2026-01-15" 1.0 1000.0 1010.0 990.0 1005.0 10000.0
            nisshokinRecord = makeNisshokinRecord "1306.T" "2026-01-15" 0.1
            records = [jquantsRecord, nisshokinRecord]
        let result = normalize testUlid testDate testTime testUlid records
        case result of
          Left normalizationError -> fail ("unexpected Left: " <> show normalizationError)
          Right normalized -> do
            length normalized `shouldBe` 1
            case normalized of
              [] -> fail "expected at least one normalized record"
              (record : _) -> normalizedRecordReverseLoanFee record `shouldBe` Just 0.1

      it "sets reverseLoanFee to Nothing when no matching nisshokin record" $ do
        let jquantsRecord = makeJQuantsRecord "9999.T" "2026-01-15" 1.0 1000.0 1010.0 990.0 1005.0 10000.0
            nisshokinRecord = makeNisshokinRecord "1306.T" "2026-01-15" 0.1
            records = [jquantsRecord, nisshokinRecord]
        let result = normalize testUlid testDate testTime testUlid records
        case result of
          Left normalizationError -> fail ("unexpected Left: " <> show normalizationError)
          Right normalized -> do
            let nonJquants = filter (\r -> normalizedRecordSymbol r == "9999.T") normalized
            case nonJquants of
              [] -> fail "no record for 9999.T"
              (record : _) -> normalizedRecordReverseLoanFee record `shouldBe` Nothing

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 1 of
  Right ulid -> ulid
  Left _ -> error "test ulid"

testDate :: Day
testDate = fromGregorian 2026 1 15

testTime :: UTCTime
testTime = UTCTime testDate 0

makeJQuantsRecord :: Text -> Text -> Double -> Double -> Double -> Double -> Double -> Double -> RawMarketRecord
makeJQuantsRecord symbol date adjustmentFactor open high low close volume =
  RawMarketRecord
    { fields =
        [ ("Code", FieldText symbol)
        , ("Date", FieldText date)
        , ("AdjustmentFactor", FieldDouble adjustmentFactor)
        , ("Open", FieldDouble open)
        , ("High", FieldDouble high)
        , ("Low", FieldDouble low)
        , ("Close", FieldDouble close)
        , ("Volume", FieldDouble volume)
        , ("Source", FieldText "jquants")
        ]
    }

makeNisshokinRecord :: Text -> Text -> Double -> RawMarketRecord
makeNisshokinRecord symbol date fee =
  RawMarketRecord
    { fields =
        [ ("Code", FieldText symbol)
        , ("Date", FieldText date)
        , ("ReverseLoanFee", FieldDouble fee)
        , ("Source", FieldText "nisshokin")
        ]
    }
