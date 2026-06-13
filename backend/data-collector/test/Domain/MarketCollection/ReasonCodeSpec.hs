module Domain.MarketCollection.ReasonCodeSpec (spec) where

import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)

spec :: Spec
spec =
  describe "Domain.MarketCollection.ReasonCode" $ do
    -- Must-10: 8値の ReasonCode 列挙型が定義されていることを確認。
    describe "ReasonCode" $ do
      it "defines all 8 required values" $ do
        RequestValidationFailed `shouldBe` RequestValidationFailed
        ComplianceSourceUnapproved `shouldBe` ComplianceSourceUnapproved
        DataSourceTimeout `shouldBe` DataSourceTimeout
        DataSourceUnavailable `shouldBe` DataSourceUnavailable
        DataSchemaInvalid `shouldBe` DataSchemaInvalid
        IdempotencyDuplicateEvent `shouldBe` IdempotencyDuplicateEvent
        StateConflict `shouldBe` StateConflict
        DependencyTimeout `shouldBe` DependencyTimeout

      it "distinguishes all values" $ do
        RequestValidationFailed `shouldNotBe` ComplianceSourceUnapproved
        DataSourceTimeout `shouldNotBe` DataSourceUnavailable
        DataSchemaInvalid `shouldNotBe` IdempotencyDuplicateEvent
        StateConflict `shouldNotBe` DependencyTimeout

      it "supports ordering" $ do
        compare RequestValidationFailed ComplianceSourceUnapproved `shouldBe` LT
