module Domain.AuditLog.ResultSpec (spec) where

import Domain.AuditLog.Result (Result (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)

spec :: Spec
spec =
  describe "Domain.AuditLog.Result" $ do
    describe "Success" $ do
      it "supports equality" $ do
        Success `shouldBe` Success
        Success `shouldNotBe` Failed

      it "supports show" $ do
        show Success `shouldBe` "Success"

    describe "Failed" $ do
      it "supports equality" $ do
        Failed `shouldBe` Failed
        Failed `shouldNotBe` Success

      it "supports show" $ do
        show Failed `shouldBe` "Failed"

    describe "Ord" $ do
      it "orders constructors by declaration order" $ do
        compare Success Failed `shouldBe` LT
        compare Failed Success `shouldBe` GT
        compare Success Success `shouldBe` EQ
