module Domain.InsightCollection.ReasonCodeSpec (spec) where

import Domain.InsightCollection.ReasonCode (ReasonCode (..), isRetryable)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "Domain.InsightCollection.ReasonCode" $ do
    -- Must-27: 7値の ReasonCode 列挙型
    describe "ReasonCode" $ do
      it "has all 7 reason codes" $ do
        RequestValidationFailed `shouldBe` RequestValidationFailed
        ComplianceSourceUnapproved `shouldBe` ComplianceSourceUnapproved
        DependencyTimeout `shouldBe` DependencyTimeout
        DependencyUnavailable `shouldBe` DependencyUnavailable
        DataSchemaInvalid `shouldBe` DataSchemaInvalid
        StateConflict `shouldBe` StateConflict
        IdempotencyDuplicateEvent `shouldBe` IdempotencyDuplicateEvent

    -- Must-28: retryable フラグ
    describe "isRetryable" $ do
      it "returns false for RequestValidationFailed" $ do
        isRetryable RequestValidationFailed `shouldBe` False

      it "returns false for ComplianceSourceUnapproved" $ do
        isRetryable ComplianceSourceUnapproved `shouldBe` False

      it "returns true for DependencyTimeout" $ do
        isRetryable DependencyTimeout `shouldBe` True

      it "returns true for DependencyUnavailable" $ do
        isRetryable DependencyUnavailable `shouldBe` True

      it "returns false for DataSchemaInvalid" $ do
        isRetryable DataSchemaInvalid `shouldBe` False

      it "returns false for StateConflict" $ do
        isRetryable StateConflict `shouldBe` False

      it "returns false for IdempotencyDuplicateEvent" $ do
        isRetryable IdempotencyDuplicateEvent `shouldBe` False
