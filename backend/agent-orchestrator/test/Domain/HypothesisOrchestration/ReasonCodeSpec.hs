module Domain.HypothesisOrchestration.ReasonCodeSpec (spec) where

import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)

spec :: Spec
spec =
  describe "Domain.HypothesisOrchestration.ReasonCode" $ do
    -- Must-34: 6値の ReasonCode テスト
    describe "ReasonCode enum" $ do
      it "has exactly 6 values" $ do
        ResourceNotFound `shouldBe` ResourceNotFound
        RequestValidationFailed `shouldBe` RequestValidationFailed
        StateConflict `shouldBe` StateConflict
        IdempotencyDuplicateEvent `shouldBe` IdempotencyDuplicateEvent
        DependencyTimeout `shouldBe` DependencyTimeout
        DependencyUnavailable `shouldBe` DependencyUnavailable

      it "values are distinct" $ do
        ResourceNotFound `shouldNotBe` RequestValidationFailed
        RequestValidationFailed `shouldNotBe` StateConflict
        StateConflict `shouldNotBe` IdempotencyDuplicateEvent
        IdempotencyDuplicateEvent `shouldNotBe` DependencyTimeout
        DependencyTimeout `shouldNotBe` DependencyUnavailable

      it "supports ordering" $ do
        compare ResourceNotFound DependencyUnavailable `shouldBe` LT

      it "RESOURCE_NOT_FOUND is distinct from REQUEST_VALIDATION_FAILED" $ do
        ResourceNotFound `shouldNotBe` RequestValidationFailed
