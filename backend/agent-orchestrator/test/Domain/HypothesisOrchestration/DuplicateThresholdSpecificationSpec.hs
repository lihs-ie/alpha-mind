module Domain.HypothesisOrchestration.DuplicateThresholdSpecificationSpec (spec) where

import Domain.HypothesisOrchestration.DuplicateThresholdSpecification (
  DuplicateThresholdSpecification (..),
  isSatisfiedBy,
 )
import Domain.HypothesisOrchestration.ValueObjects (
  DuplicateAssessment,
  DuplicateAssessmentDecision (..),
  mkDuplicateAssessment,
 )
import Test.Hspec (Spec, describe, it, shouldBe)

mkAssessment :: Double -> DuplicateAssessment
mkAssessment score =
  mkDuplicateAssessment "hash-001" score 0.8 Allow Nothing

testSpecification :: DuplicateThresholdSpecification
testSpecification = DuplicateThresholdSpecification{threshold = 0.8}

spec :: Spec
spec =
  describe "Domain.HypothesisOrchestration.DuplicateThresholdSpecification (Must-29)" $ do
    describe "isSatisfiedBy" $ do
      -- Must-29: 閾値以上のスコアは True
      it "returns True when maxSimilarityScore >= threshold (Must-29)" $ do
        isSatisfiedBy testSpecification (mkAssessment 0.9) `shouldBe` True

      it "returns True when maxSimilarityScore == threshold exactly (Must-29)" $ do
        isSatisfiedBy testSpecification (mkAssessment 0.8) `shouldBe` True

      -- Must-29: 閾値未満のスコアは False
      it "returns False when maxSimilarityScore < threshold (Must-29)" $ do
        isSatisfiedBy testSpecification (mkAssessment 0.5) `shouldBe` False

      it "returns False when maxSimilarityScore is 0.0 (Must-29)" $ do
        isSatisfiedBy testSpecification (mkAssessment 0.0) `shouldBe` False

      -- 境界値テスト
      it "handles boundary value just below threshold" $ do
        isSatisfiedBy testSpecification (mkAssessment 0.799) `shouldBe` False

      it "handles boundary value just above threshold" $ do
        isSatisfiedBy testSpecification (mkAssessment 0.801) `shouldBe` True

      -- 異なる閾値での動作確認
      it "respects different threshold values" $ do
        let strictSpecification = DuplicateThresholdSpecification{threshold = 0.95}
        isSatisfiedBy strictSpecification (mkAssessment 0.9) `shouldBe` False
        isSatisfiedBy strictSpecification (mkAssessment 0.95) `shouldBe` True
        isSatisfiedBy strictSpecification (mkAssessment 1.0) `shouldBe` True
