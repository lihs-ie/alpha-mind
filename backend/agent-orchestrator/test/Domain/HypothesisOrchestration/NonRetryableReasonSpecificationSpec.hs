module Domain.HypothesisOrchestration.NonRetryableReasonSpecificationSpec (spec) where

import Domain.HypothesisOrchestration.NonRetryableReasonSpecification (
  NonRetryableReasonSpecification (..),
  isSatisfiedBy,
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe)

testSpecification :: NonRetryableReasonSpecification
testSpecification = NonRetryableReasonSpecification

spec :: Spec
spec =
  describe "Domain.HypothesisOrchestration.NonRetryableReasonSpecification (Must-30)" $ do
    describe "isSatisfiedBy (RULE-AO-008)" $ do
      -- Must-30: RESOURCE_NOT_FOUND は非再試行
      it "returns True for RESOURCE_NOT_FOUND (Must-30 RULE-AO-008)" $ do
        isSatisfiedBy testSpecification ResourceNotFound `shouldBe` True

      -- Must-30: REQUEST_VALIDATION_FAILED は非再試行
      it "returns True for REQUEST_VALIDATION_FAILED (Must-30 RULE-AO-008)" $ do
        isSatisfiedBy testSpecification RequestValidationFailed `shouldBe` True

      -- Must-30: STATE_CONFLICT は再試行可能（False）
      it "returns False for STATE_CONFLICT" $ do
        isSatisfiedBy testSpecification StateConflict `shouldBe` False

      -- Must-30: IDEMPOTENCY_DUPLICATE_EVENT は再試行可能（False）
      it "returns False for IDEMPOTENCY_DUPLICATE_EVENT" $ do
        isSatisfiedBy testSpecification IdempotencyDuplicateEvent `shouldBe` False

      -- Must-30: DEPENDENCY_TIMEOUT は再試行可能（False）
      it "returns False for DEPENDENCY_TIMEOUT" $ do
        isSatisfiedBy testSpecification DependencyTimeout `shouldBe` False

      -- Must-30: DEPENDENCY_UNAVAILABLE は再試行可能（False）
      it "returns False for DEPENDENCY_UNAVAILABLE" $ do
        isSatisfiedBy testSpecification DependencyUnavailable `shouldBe` False
