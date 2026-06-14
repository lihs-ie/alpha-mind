{-# LANGUAGE FieldSelectors #-}
{-# LANGUAGE OverloadedRecordDot #-}

{- | Pure normalization functions for J-Quants market data.

Must-06: Reject records with AdjustmentFactor <= 0 or missing.
Must-07: Per-symbol cumulative-product + shift adjustment (§8.2.1.1).
Must-08: Inner join with nisshokin (reverseLoanFee) by symbol × targetDate.
Must-09: Map to §8.4 NormalizedRecord schema and serialize as NDJSON.
-}
module Infrastructure.Normalization.MarketDataNormalizer (
  -- * Output type
  NormalizedRecord (..),
  normalizedRecordTargetDate,
  normalizedRecordSymbol,
  normalizedRecordOpen,
  normalizedRecordAdjustmentCumFactor,
  normalizedRecordAdjustmentBaseDate,
  normalizedRecordReverseLoanFee,

  -- * Pure normalization
  normalize,

  -- * NDJSON serialization
  encodeNdjson,
) where

import Data.Aeson (ToJSON (..), encode, object, (.=))
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.List (sortBy)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Ord (Down (..), comparing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (Day, UTCTime)
import Data.ULID (ULID)
import Domain.MarketCollection.CollectionQualityPolicy (RawMarketField (..), RawMarketRecord (..))

-- ---------------------------------------------------------------------------
-- §8.4 Normalized schema
-- ---------------------------------------------------------------------------

data NormalizedRecord = NormalizedRecord
  { identifier :: ULID
  , targetDate :: Day
  , symbol :: Text
  , market :: Maybe Text
  , open :: Double
  , high :: Double
  , low :: Double
  , close :: Double
  , volume :: Double
  , openRaw :: Double
  , highRaw :: Double
  , lowRaw :: Double
  , closeRaw :: Double
  , volumeRaw :: Double
  , adjustmentCumFactor :: Double
  , adjustmentBaseDate :: Day
  , reverseLoanFee :: Maybe Double
  , source :: Text
  , collectedAt :: UTCTime
  , trace :: ULID
  }
  deriving stock (Eq, Show)

-- | Accessor functions for test inspection (safe accessors without OverloadedRecordDot dependency)
normalizedRecordTargetDate :: NormalizedRecord -> Day
normalizedRecordTargetDate (NormalizedRecord{targetDate = date}) = date

normalizedRecordSymbol :: NormalizedRecord -> Text
normalizedRecordSymbol (NormalizedRecord{symbol = symbolCode}) = symbolCode

normalizedRecordOpen :: NormalizedRecord -> Double
normalizedRecordOpen (NormalizedRecord{open = openPrice}) = openPrice

normalizedRecordAdjustmentCumFactor :: NormalizedRecord -> Double
normalizedRecordAdjustmentCumFactor (NormalizedRecord{adjustmentCumFactor = cumulativeFactor}) = cumulativeFactor

normalizedRecordAdjustmentBaseDate :: NormalizedRecord -> Day
normalizedRecordAdjustmentBaseDate (NormalizedRecord{adjustmentBaseDate = baseDate}) = baseDate

normalizedRecordReverseLoanFee :: NormalizedRecord -> Maybe Double
normalizedRecordReverseLoanFee (NormalizedRecord{reverseLoanFee = reverseLoanFeeValue}) = reverseLoanFeeValue

instance ToJSON NormalizedRecord where
  toJSON record =
    object
      [ "identifier" .= show record.identifier
      , "targetDate" .= record.targetDate
      , "symbol" .= record.symbol
      , "market" .= record.market
      , "open" .= record.open
      , "high" .= record.high
      , "low" .= record.low
      , "close" .= record.close
      , "volume" .= record.volume
      , "openRaw" .= record.openRaw
      , "highRaw" .= record.highRaw
      , "lowRaw" .= record.lowRaw
      , "closeRaw" .= record.closeRaw
      , "volumeRaw" .= record.volumeRaw
      , "adjustmentCumFactor" .= record.adjustmentCumFactor
      , "adjustmentBaseDate" .= record.adjustmentBaseDate
      , "reverseLoanFee" .= record.reverseLoanFee
      , "source" .= record.source
      , "collectedAt" .= record.collectedAt
      , "trace" .= show record.trace
      ]

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

{- | Normalize raw market records.

1. Validate AdjustmentFactor (Must-06).
2. Per-symbol cumprod+shift adjustment (Must-07).
3. Inner join with nisshokin for reverseLoanFee (Must-08).
4. Map to NormalizedRecord (Must-09).

The caller must supply:
  - @allRecords@: all records (jquants + nisshokin mixed).
  - @eventIdentifier@: ULID for the collection event (used as record identifier).
  - @targetDay@: the collection target date.
  - @collectionTime@: timestamp for collectedAt.
  - @traceValue@: trace ULID.
-}
normalize ::
  ULID ->
  Day ->
  UTCTime ->
  ULID ->
  [RawMarketRecord] ->
  Either Text [NormalizedRecord]
normalize eventIdentifier targetDay collectionTime traceValue allRecords = do
  let jquantsRecords = filter (isSource "jquants") allRecords
      nisshokinRecords = filter (isSource "nisshokin") allRecords

  -- Must-06: validate AdjustmentFactor for jquants records
  mapM_ (validateAdjustmentFactor . extractFields) jquantsRecords

  -- Must-07: per-symbol cumprod+shift
  let grouped = groupBySymbol jquantsRecords
  adjustedGroups <- mapM adjustSymbol grouped

  -- Must-08: build reverseLoanFee lookup from nisshokin
  let feeMap = buildFeeMap nisshokinRecords

  -- Must-09: map to NormalizedRecord
  let normalizedRecords =
        concatMap
          ( \(symbolCode, rows) ->
              map (toNormalizedRecord eventIdentifier targetDay collectionTime traceValue symbolCode feeMap) rows
          )
          (Map.toList adjustedGroups)
  pure normalizedRecords

-- ---------------------------------------------------------------------------
-- NDJSON serialization
-- ---------------------------------------------------------------------------

encodeNdjson :: [NormalizedRecord] -> ByteString
encodeNdjson records =
  ByteString.Lazy.intercalate "\n" (map encode records)
    <> if null records then ByteString.Lazy.empty else "\n"

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

type FieldMap = [(Text, RawMarketField)]
type SymbolKey = Text

extractFields :: RawMarketRecord -> FieldMap
extractFields record = record.fields

isSource :: Text -> RawMarketRecord -> Bool
isSource sourceValue record =
  case lookup "Source" record.fields of
    Just (FieldText text) -> text == sourceValue
    _ -> False

getTextField :: Text -> FieldMap -> Maybe Text
getTextField key fields =
  case lookup key fields of
    Just (FieldText text) -> Just text
    _ -> Nothing

getDoubleField :: Text -> FieldMap -> Maybe Double
getDoubleField key fields =
  case lookup key fields of
    Just (FieldDouble double) -> Just double
    Just (FieldInt integer) -> Just (fromIntegral integer)
    _ -> Nothing

getDateField :: Text -> FieldMap -> Maybe Day
getDateField key fields =
  case lookup key fields of
    Just (FieldText text) ->
      case reads (Text.unpack text) of
        [(day, "")] -> Just day
        _ -> Nothing
    _ -> Nothing

-- Must-06
validateAdjustmentFactor :: FieldMap -> Either Text ()
validateAdjustmentFactor fields =
  case getDoubleField "AdjustmentFactor" fields of
    Nothing ->
      Left "DATA_SCHEMA_INVALID: AdjustmentFactor <= 0 or missing"
    Just factor
      | factor <= 0 ->
          Left "DATA_SCHEMA_INVALID: AdjustmentFactor <= 0 or missing"
    Just _ -> Right ()

groupBySymbol :: [RawMarketRecord] -> Map SymbolKey [RawMarketRecord]
groupBySymbol = foldr insertRecord Map.empty
 where
  insertRecord record accumulator =
    case getTextField "Code" record.fields of
      Nothing -> accumulator
      Just symbolCode -> Map.insertWith (<>) symbolCode [record] accumulator

-- Must-07: per-symbol cumprod+shift adjustment
data AdjRow = AdjRow
  { adjRowDate :: Day
  , adjRowAdjustmentFactor :: Double
  , adjRowOpen :: Double
  , adjRowHigh :: Double
  , adjRowLow :: Double
  , adjRowClose :: Double
  , adjRowVolume :: Double
  , adjRowFields :: FieldMap
  , adjCumFactor :: Double
  }

adjustSymbol :: [RawMarketRecord] -> Either Text [AdjRow]
adjustSymbol records = do
  rows <- mapM parseRow records
  -- Step 1: sort Date descending (newest first)
  let sorted = sortBy (comparing (Data.Ord.Down . adjRowDate)) rows
  -- Step 2: cumulative product of AdjustmentFactor (descending)
  let cumFactors = scanl1 (*) (map adjRowAdjustmentFactor sorted)
  -- Step 3: shift right by 1, fill head with 1.0
  let shiftedCumFactors = 1.0 : init cumFactors
  -- Step 4/5: apply
  let adjusted = zipWith applyFactor sorted shiftedCumFactors
  pure adjusted
 where
  parseRow record = do
    let fields = record.fields
    rowDate <-
      maybe (Left "missing Date field") Right (getDateField "Date" fields)
    factor <-
      maybe (Left "DATA_SCHEMA_INVALID: AdjustmentFactor <= 0 or missing") Right (getDoubleField "AdjustmentFactor" fields)
    rowOpen <-
      maybe (Left "missing Open field") Right (getDoubleField "Open" fields)
    rowHigh <-
      maybe (Left "missing High field") Right (getDoubleField "High" fields)
    rowLow <-
      maybe (Left "missing Low field") Right (getDoubleField "Low" fields)
    rowClose <-
      maybe (Left "missing Close field") Right (getDoubleField "Close" fields)
    rowVolume <-
      maybe (Left "missing Volume field") Right (getDoubleField "Volume" fields)
    pure
      AdjRow
        { adjRowDate = rowDate
        , adjRowAdjustmentFactor = factor
        , adjRowOpen = rowOpen
        , adjRowHigh = rowHigh
        , adjRowLow = rowLow
        , adjRowClose = rowClose
        , adjRowVolume = rowVolume
        , adjRowFields = fields
        , adjCumFactor = 1.0
        }

  applyFactor row cumFactor =
    row
      { adjRowOpen = row.adjRowOpen * cumFactor
      , adjRowHigh = row.adjRowHigh * cumFactor
      , adjRowLow = row.adjRowLow * cumFactor
      , adjRowClose = row.adjRowClose * cumFactor
      , adjRowVolume = if cumFactor /= 0 then row.adjRowVolume / cumFactor else row.adjRowVolume
      , adjCumFactor = cumFactor
      }

-- Must-08: reverseLoanFee lookup (symbol x targetDate)
type FeeKey = (Text, Day)

buildFeeMap :: [RawMarketRecord] -> Map FeeKey Double
buildFeeMap records =
  Map.fromList (mapMaybe extractFee records)
 where
  extractFee record =
    let fields = record.fields
     in do
          sym <- getTextField "Code" fields
          date <- getDateField "Date" fields
          fee <- getDoubleField "ReverseLoanFee" fields
          pure ((sym, date), fee)

-- Must-09: map AdjRow to NormalizedRecord
toNormalizedRecord ::
  ULID ->
  Day ->
  UTCTime ->
  ULID ->
  SymbolKey ->
  Map FeeKey Double ->
  AdjRow ->
  NormalizedRecord
toNormalizedRecord eventIdentifier collectionTargetDay collectionTime traceValue sym feeMap row =
  NormalizedRecord
    { identifier = eventIdentifier
    , targetDate = row.adjRowDate
    , symbol = sym
    , market = getTextField "Market" row.adjRowFields
    , open = row.adjRowOpen
    , high = row.adjRowHigh
    , low = row.adjRowLow
    , close = row.adjRowClose
    , volume = row.adjRowVolume
    , openRaw = row.adjRowOpen / safeOr1 row.adjCumFactor
    , highRaw = row.adjRowHigh / safeOr1 row.adjCumFactor
    , lowRaw = row.adjRowLow / safeOr1 row.adjCumFactor
    , closeRaw = row.adjRowClose / safeOr1 row.adjCumFactor
    , volumeRaw = row.adjRowVolume * safeOr1 row.adjCumFactor
    , adjustmentCumFactor = row.adjCumFactor
    , adjustmentBaseDate = collectionTargetDay
    , reverseLoanFee = Map.lookup (sym, row.adjRowDate) feeMap
    , source = fromMaybe "jquants" (getTextField "Source" row.adjRowFields)
    , collectedAt = collectionTime
    , trace = traceValue
    }

safeOr1 :: Double -> Double
safeOr1 x = if x == 0 then 1.0 else x
