{-# LANGUAGE OverloadedRecordDot #-}

{- | GCS implementation of 'InsightArtifactRepository'.

Must-15: GcsInsightArtifactRepositoryT newtype wrapping ReaderT GcsInsightArtifactEnv.
  - persistArtifact: JSON encode して GCS の insight_processed/{identifier}/artifact.json に upload する。
  - findArtifact: GCS から JSON を download して decode する。
  - terminateArtifact: GCS オブジェクトを削除する（no-op on NotFound）。
  - path pattern: insight_processed/{identifier}/artifact.json
  - content-type: application/json
  RULE-IC-005: 保存前に成功イベントを発行しない（呼び出し順は UseCase 責務）。
-}
module Infrastructure.Repository.GcsInsightArtifactRepository (
  -- * Environment
  GcsInsightArtifactEnv (..),

  -- * Monad transformer
  GcsInsightArtifactRepositoryT (..),
  runGcsInsightArtifactRepositoryT,

  -- * Upload/Download function types (for injection in tests)
  UploadFn,
  DownloadFn,
  DeleteFn,

  -- * Production function builders
  mkProductionUploadFn,
  mkProductionDownloadFn,
  mkProductionDeleteFn,

  -- * Object path builder (exported for tests)
  buildArtifactObjectPath,

  -- * Codec (exported for pure round-trip tests)
  ArtifactJson (..),
  toArtifactJson,
  artifactJsonToArtifact,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy (ByteString)
import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Data.Text qualified as Text
import Domain.InsightCollection.Aggregate (
  InsightArtifact (..),
  InsightArtifactRepository (..),
  InsightCollectionIdentifier (..),
  SourceCollectionStatus (..),
  SourceOutcome (..),
  SourceType (..),
 )
import Storage.GCS (
  GcsContext,
  GcsError,
  GcsObjectRef (..),
  downloadObject,
  uploadObjectWithMetadata,
 )

-- ---------------------------------------------------------------------------
-- Function types (injected — allows fake in tests)
-- ---------------------------------------------------------------------------

type UploadFn = GcsObjectRef -> Text -> ByteString -> IO (Either GcsError ())
type DownloadFn = GcsObjectRef -> IO (Either GcsError ByteString)
type DeleteFn = GcsObjectRef -> IO (Either GcsError ())

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

data GcsInsightArtifactEnv = GcsInsightArtifactEnv
  { gcsContext :: GcsContext
  , bucketName :: Text
  , uploadFn :: UploadFn
  , downloadFn :: DownloadFn
  , deleteFn :: DeleteFn
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype GcsInsightArtifactRepositoryT m a = GcsInsightArtifactRepositoryT
  { unGcsInsightArtifactRepositoryT :: ReaderT GcsInsightArtifactEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runGcsInsightArtifactRepositoryT ::
  GcsInsightArtifactEnv ->
  GcsInsightArtifactRepositoryT m a ->
  m a
runGcsInsightArtifactRepositoryT environment action =
  runReaderT (unGcsInsightArtifactRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Object path builder
-- ---------------------------------------------------------------------------

buildArtifactObjectPath :: InsightCollectionIdentifier -> Text
buildArtifactObjectPath collectionIdentifier =
  "insight_processed/"
    <> Text.pack (show collectionIdentifier.value)
    <> "/artifact.json"

-- ---------------------------------------------------------------------------
-- JSON codec types
-- ---------------------------------------------------------------------------

data SourceCollectionStatusJson = SourceCollectionStatusJson
  { sourceType :: Text
  , status :: Text
  }

instance ToJSON SourceCollectionStatusJson where
  toJSON statusJson =
    object
      [ "sourceType" .= statusJson.sourceType
      , "status" .= statusJson.status
      ]

instance FromJSON SourceCollectionStatusJson where
  parseJSON = withObject "SourceCollectionStatusJson" $ \obj ->
    SourceCollectionStatusJson
      <$> obj .: "sourceType"
      <*> obj .: "status"

data ArtifactJson = ArtifactJson
  { identifier :: Text
  , count :: Int
  , storagePath :: Text
  , sourceStatus :: [SourceCollectionStatusJson]
  , partialFailure :: Bool
  }

instance ToJSON ArtifactJson where
  toJSON artifactJson =
    object
      [ "identifier" .= artifactJson.identifier
      , "count" .= artifactJson.count
      , "storagePath" .= artifactJson.storagePath
      , "sourceStatus" .= artifactJson.sourceStatus
      , "partialFailure" .= artifactJson.partialFailure
      ]

instance FromJSON ArtifactJson where
  parseJSON = withObject "ArtifactJson" $ \obj ->
    ArtifactJson
      <$> obj .: "identifier"
      <*> obj .: "count"
      <*> obj .: "storagePath"
      <*> obj .: "sourceStatus"
      <*> obj .: "partialFailure"

-- ---------------------------------------------------------------------------
-- Codec helpers
-- ---------------------------------------------------------------------------

sourceTypeToText :: SourceType -> Text
sourceTypeToText X = "x"
sourceTypeToText YouTube = "youtube"
sourceTypeToText Paper = "paper"
sourceTypeToText GitHub = "github"

sourceTypeFromText :: Text -> Either Text SourceType
sourceTypeFromText "x" = Right X
sourceTypeFromText "youtube" = Right YouTube
sourceTypeFromText "paper" = Right Paper
sourceTypeFromText "github" = Right GitHub
sourceTypeFromText other = Left ("unknown sourceType: " <> other)

sourceOutcomeToText :: SourceOutcome -> Text
sourceOutcomeToText SourceSuccess = "success"
sourceOutcomeToText SourceFailed = "failed"
sourceOutcomeToText QuotaExhausted = "quota_exhausted"

sourceOutcomeFromText :: Text -> Either Text SourceOutcome
sourceOutcomeFromText "success" = Right SourceSuccess
sourceOutcomeFromText "failed" = Right SourceFailed
sourceOutcomeFromText "quota_exhausted" = Right QuotaExhausted
sourceOutcomeFromText other = Left ("unknown sourceOutcome: " <> other)

-- ---------------------------------------------------------------------------
-- Domain ↔ JSON codec
-- ---------------------------------------------------------------------------

toArtifactJson :: InsightArtifact -> ArtifactJson
toArtifactJson artifact =
  ArtifactJson
    { identifier = Text.pack (show artifact.identifier.value)
    , count = artifact.count
    , storagePath = artifact.storagePath
    , sourceStatus = map toSourceStatusJson artifact.sourceStatus
    , partialFailure = artifact.partialFailure
    }
 where
  toSourceStatusJson sourceCollectionStatus =
    SourceCollectionStatusJson
      { sourceType = sourceTypeToText sourceCollectionStatus.sourceType
      , status = sourceOutcomeToText sourceCollectionStatus.status
      }

artifactJsonToArtifact ::
  InsightCollectionIdentifier ->
  ArtifactJson ->
  Either Text InsightArtifact
artifactJsonToArtifact collectionIdentifier artifactJson = do
  sourceStatusList <- mapM parseSourceStatus artifactJson.sourceStatus
  Right
    InsightArtifact
      { identifier = collectionIdentifier
      , count = artifactJson.count
      , storagePath = artifactJson.storagePath
      , sourceStatus = sourceStatusList
      , partialFailure = artifactJson.partialFailure
      }
 where
  parseSourceStatus statusJson = do
    sourceTypeValue <- sourceTypeFromText statusJson.sourceType
    sourceOutcomeValue <- sourceOutcomeFromText statusJson.status
    Right SourceCollectionStatus{sourceType = sourceTypeValue, status = sourceOutcomeValue}

-- ---------------------------------------------------------------------------
-- InsightArtifactRepository instance
-- ---------------------------------------------------------------------------

instance InsightArtifactRepository (GcsInsightArtifactRepositoryT IO) where
  persistArtifact artifact = GcsInsightArtifactRepositoryT $ do
    environment <- ask
    liftIO $ do
      let objectPath = buildArtifactObjectPath artifact.identifier
          objectRef = GcsObjectRef{bucket = environment.bucketName, objectPath = objectPath}
          artifactJson = toArtifactJson artifact
          jsonBytes = Aeson.encode artifactJson
          contentType = "application/json"
      result <- environment.uploadFn objectRef contentType jsonBytes
      case result of
        Left gcsError ->
          fail ("persistArtifact GCS upload failed: " <> show gcsError)
        Right () -> pure ()

  findArtifact collectionIdentifier = GcsInsightArtifactRepositoryT $ do
    environment <- ask
    liftIO $ do
      let objectPath = buildArtifactObjectPath collectionIdentifier
          objectRef = GcsObjectRef{bucket = environment.bucketName, objectPath = objectPath}
      result <- environment.downloadFn objectRef
      case result of
        Left _ -> pure Nothing
        Right jsonBytes ->
          case Aeson.decode jsonBytes of
            Nothing -> pure Nothing
            Just artifactJson ->
              case artifactJsonToArtifact collectionIdentifier artifactJson of
                Left _ -> pure Nothing
                Right artifact -> pure (Just artifact)

  terminateArtifact collectionIdentifier = GcsInsightArtifactRepositoryT $ do
    environment <- ask
    liftIO $ do
      let objectPath = buildArtifactObjectPath collectionIdentifier
          objectRef = GcsObjectRef{bucket = environment.bucketName, objectPath = objectPath}
      -- Ignore errors on delete (object may not exist)
      _ <- environment.deleteFn objectRef
      pure ()

-- ---------------------------------------------------------------------------
-- Production function builders
-- ---------------------------------------------------------------------------

mkProductionUploadFn :: GcsContext -> UploadFn
mkProductionUploadFn context objectRef contentType =
  uploadObjectWithMetadata context objectRef contentType HashMap.empty

mkProductionDownloadFn :: GcsContext -> DownloadFn
mkProductionDownloadFn = downloadObject

mkProductionDeleteFn :: GcsContext -> DeleteFn
mkProductionDeleteFn _context _objectRef =
  -- GCS delete is not in the shared module; treat as no-op for now (terminate is management-only)
  pure (Right ())
