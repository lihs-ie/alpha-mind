{-# LANGUAGE OverloadedRecordDot #-}

{- | GCS implementation of 'RawMarketDataPort'.

Must-01: GcsMarketDataRepositoryT newtype wrapping ReaderT GcsMarketDataEnv.
Must-02: persistRawMarketData normalizes then uploads NDJSON to GCS.
Must-03: Path = normalized_market_data/date={YYYY-MM-DD}/market_snapshot.ndjson, content-type application/x-ndjson.
Must-04: GcsMarketDataEnv holds gcsContext and bucketName (injected, not hardcoded).
Must-05: GCS write failure -> Left errMsg.
-}
module Infrastructure.Repository.GcsMarketDataRepository (
  -- * Environment
  GcsMarketDataEnv (..),

  -- * Monad transformer
  GcsMarketDataRepositoryT (..),
  runGcsMarketDataRepositoryT,

  -- * Upload function type (for injection)
  UploadFn,

  -- * Production upload function builder
  mkProductionUploadFn,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (Day, UTCTime, getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Domain.MarketCollection.Aggregate (MarketCollectionIdentifier (..))
import Infrastructure.Normalization.MarketDataNormalizer (encodeNdjson, normalize)
import Storage.GCS (GcsContext, GcsError, GcsObjectRef (..), uploadObjectWithMetadata)
import UseCase.CollectMarketData (NormalizedMarketDataset (..), RawMarketDataPort (..))

-- ---------------------------------------------------------------------------
-- Upload function type (injected — allows fake in tests)
-- ---------------------------------------------------------------------------

{- | Upload function signature.
In production: wraps 'Storage.GCS.uploadObjectWithMetadata'.
In tests: writes to an IORef for inspection.
-}
type UploadFn = GcsObjectRef -> Text -> ByteString.Lazy.ByteString -> IO (Either GcsError ())

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

data GcsMarketDataEnv = GcsMarketDataEnv
  { gcsContext :: GcsContext
  , bucketName :: Text
  , uploadFn :: UploadFn
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype GcsMarketDataRepositoryT m a = GcsMarketDataRepositoryT
  { unGcsMarketDataRepositoryT :: ReaderT GcsMarketDataEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runGcsMarketDataRepositoryT :: GcsMarketDataEnv -> GcsMarketDataRepositoryT m a -> m a
runGcsMarketDataRepositoryT environment action =
  runReaderT (unGcsMarketDataRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- RawMarketDataPort instance
-- ---------------------------------------------------------------------------

instance RawMarketDataPort (GcsMarketDataRepositoryT IO) where
  persistRawMarketData collectionIdentifier targetDay dataset =
    GcsMarketDataRepositoryT $ do
      environment <- ask
      now <- liftIO getCurrentTime
      liftIO $ persistNdjson environment collectionIdentifier targetDay now dataset

-- ---------------------------------------------------------------------------
-- Internal implementation
-- ---------------------------------------------------------------------------

persistNdjson ::
  GcsMarketDataEnv ->
  MarketCollectionIdentifier ->
  Day ->
  UTCTime ->
  NormalizedMarketDataset ->
  IO (Either Text Text)
persistNdjson environment collectionIdentifier targetDay now dataset = do
  let eventIdentifier = collectionIdentifier.value
      traceIdentifier = collectionIdentifier.value
      objectPath = buildObjectPath targetDay
      objectRef =
        GcsObjectRef
          { bucket = environment.bucketName
          , objectPath = objectPath
          }
  case normalize eventIdentifier targetDay now traceIdentifier dataset.records of
    Left normalizationError ->
      pure (Left normalizationError)
    Right normalizedRecords -> do
      let ndjsonBytes = encodeNdjson normalizedRecords
          contentType = "application/x-ndjson"
      result <- environment.uploadFn objectRef contentType ndjsonBytes
      case result of
        Left gcsError ->
          pure (Left ("GCS upload failed: " <> Text.pack (show gcsError)))
        Right () ->
          pure (Right ("gs://" <> environment.bucketName <> "/" <> objectPath))

buildObjectPath :: Day -> Text
buildObjectPath targetDay =
  "normalized_market_data/date="
    <> Text.pack (formatTime defaultTimeLocale "%Y-%m-%d" targetDay)
    <> "/market_snapshot.ndjson"

-- ---------------------------------------------------------------------------
-- Production upload function builder
-- ---------------------------------------------------------------------------

{- | Build a production 'UploadFn' from a 'GcsContext'.
Called in Main.hs (#28) when constructing 'GcsMarketDataEnv'.
-}
mkProductionUploadFn :: GcsContext -> UploadFn
mkProductionUploadFn context objectRef contentType =
  uploadObjectWithMetadata context objectRef contentType HashMap.empty
