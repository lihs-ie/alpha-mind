module Infrastructure.Repository.GcsInsightArtifactRepositorySpec (spec) where

import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.ULID (ulidFromInteger)
import Domain.InsightCollection.Aggregate (
  InsightArtifact (..),
  InsightArtifactRepository (..),
  InsightCollectionIdentifier (..),
  SourceCollectionStatus (..),
  SourceOutcome (..),
  SourceType (..),
 )
import Infrastructure.Repository.GcsInsightArtifactRepository (
  GcsInsightArtifactEnv (..),
  UploadFn,
  artifactJsonToArtifact,
  buildArtifactObjectPath,
  runGcsInsightArtifactRepositoryT,
  toArtifactJson,
 )
import Storage.GCS (GcsObjectRef (..), defaultGcsContext)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

sampleIdentifier :: InsightCollectionIdentifier
sampleIdentifier =
  InsightCollectionIdentifier
    { value = case ulidFromInteger 2001 of Right u -> u; Left _ -> error "ulid"
    }

sampleArtifact :: InsightArtifact
sampleArtifact =
  InsightArtifact
    { identifier = sampleIdentifier
    , count = 5
    , storagePath = "gs://test-bucket/insight_processed/01JXYZ/artifact.json"
    , sourceStatus =
        [ SourceCollectionStatus{sourceType = X, status = SourceSuccess}
        , SourceCollectionStatus{sourceType = GitHub, status = SourceFailed}
        ]
    , partialFailure = True
    }

hasPrefix :: Text -> Text -> Bool
hasPrefix = Text.isPrefixOf

hasSuffix :: Text -> Text -> Bool
hasSuffix = Text.isSuffixOf

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "GcsInsightArtifactRepositoryT" $ do
    describe "buildArtifactObjectPath" $ do
      it "builds path prefixed with insight_processed/" $ do
        let path = buildArtifactObjectPath sampleIdentifier
        path `shouldSatisfy` hasPrefix "insight_processed/"

      it "builds path suffixed with /artifact.json" $ do
        let path = buildArtifactObjectPath sampleIdentifier
        path `shouldSatisfy` hasSuffix "/artifact.json"

    describe "toArtifactJson / artifactJsonToArtifact round-trip" $ do
      it "round-trips count and storagePath" $ do
        let artifactJson = toArtifactJson sampleArtifact
        case artifactJsonToArtifact sampleIdentifier artifactJson of
          Left errMsg -> fail ("artifactJsonToArtifact failed: " <> show errMsg)
          Right decoded -> do
            decoded.count `shouldBe` sampleArtifact.count
            decoded.storagePath `shouldBe` sampleArtifact.storagePath

      it "round-trips partialFailure" $ do
        let artifactJson = toArtifactJson sampleArtifact
        case artifactJsonToArtifact sampleIdentifier artifactJson of
          Left errMsg -> fail ("artifactJsonToArtifact failed: " <> show errMsg)
          Right decoded ->
            decoded.partialFailure `shouldBe` sampleArtifact.partialFailure

      it "round-trips all SourceType values in sourceStatus" $ do
        let artifact =
              sampleArtifact
                { sourceStatus =
                    [ SourceCollectionStatus{sourceType = X, status = SourceSuccess}
                    , SourceCollectionStatus{sourceType = YouTube, status = QuotaExhausted}
                    , SourceCollectionStatus{sourceType = Paper, status = SourceFailed}
                    , SourceCollectionStatus{sourceType = GitHub, status = SourceSuccess}
                    ]
                }
            artifactJson = toArtifactJson artifact
        case artifactJsonToArtifact sampleIdentifier artifactJson of
          Left errMsg -> fail ("artifactJsonToArtifact failed: " <> show errMsg)
          Right decoded ->
            length decoded.sourceStatus `shouldBe` 4

      it "round-trips SourceOutcome values" $ do
        let artifactJson = toArtifactJson sampleArtifact
        case artifactJsonToArtifact sampleIdentifier artifactJson of
          Left errMsg -> fail ("artifactJsonToArtifact failed: " <> show errMsg)
          Right decoded -> do
            let outcomes = map (.status) decoded.sourceStatus
            outcomes `shouldSatisfy` elem SourceSuccess
            outcomes `shouldSatisfy` elem SourceFailed

    describe "persistArtifact (fake upload)" $ do
      it "calls uploadFn with correct bucket, path, and application/json content-type" $ do
        capturedRef <- newIORef Nothing
        let fakeUploadFn :: UploadFn
            fakeUploadFn objectRef contentType _body = do
              writeIORef capturedRef (Just (objectRef, contentType))
              pure (Right ())
            fakeDownloadFn _ref = pure (Left (error "not used in this test"))
            fakeDeleteFn _ref = pure (Right ())
            bucketNameValue = "test-bucket" :: Text
            environment =
              GcsInsightArtifactEnv
                { gcsContext = defaultGcsContext
                , bucketName = bucketNameValue
                , uploadFn = fakeUploadFn
                , downloadFn = fakeDownloadFn
                , deleteFn = fakeDeleteFn
                }
        runGcsInsightArtifactRepositoryT environment $
          persistArtifact sampleArtifact
        captured <- readIORef capturedRef
        case captured of
          Nothing -> fail "uploadFn was not called"
          Just (objectRef, contentType) -> do
            objectRef.bucket `shouldBe` bucketNameValue
            objectRef.objectPath `shouldSatisfy` hasPrefix "insight_processed/"
            contentType `shouldBe` "application/json"
