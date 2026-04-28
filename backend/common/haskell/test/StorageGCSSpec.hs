{-# LANGUAGE OverloadedStrings #-}

module StorageGCSSpec (spec) where

import Resilience.Retry (RetryPolicyConfig (..))
import Storage.GCS (
  GcsContext (..),
  GcsError (..),
  GcsObjectRef (..),
  defaultGcsContext,
  parseGsUri,
  uploadObject,
 )
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "Storage.GCS" $ do
    it "parses valid gs:// object references and normalizes leading slashes" $
      parseGsUri "gs://alpha-bucket//path/to/file.json"
        `shouldBe` Right GcsObjectRef{bucket = "alpha-bucket", objectPath = "path/to/file.json"}

    it "rejects unsupported URI schemes" $
      parseGsUri "https://alpha-bucket/path"
        `shouldBe` Left (InvalidGsUri "https://alpha-bucket/path")

    it "rejects missing buckets" $
      parseGsUri "gs:///path"
        `shouldBe` Left (BucketMissing "gs:///path")

    it "rejects missing object paths" $
      parseGsUri "gs://alpha-bucket"
        `shouldBe` Left (ObjectPathMissing "gs://alpha-bucket")

    it "provides the default retry context" $
      defaultGcsContext
        `shouldBe` GcsContext{retryPolicyConfig = RetryPolicyConfig{maxRetries = 3, baseDelayMicros = 100_000}}

    it "rejects invalid upload content types before creating a GCS environment" $ do
      result <-
        uploadObject
          GcsContext{retryPolicyConfig = RetryPolicyConfig{maxRetries = 0, baseDelayMicros = 0}}
          GcsObjectRef{bucket = "alpha-bucket", objectPath = "file.txt"}
          "not-a-content-type"
          "payload"
      result `shouldBe` Left (InvalidContentType "not-a-content-type")
