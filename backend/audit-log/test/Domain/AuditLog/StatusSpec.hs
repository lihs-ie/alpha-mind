module Domain.AuditLog.StatusSpec (spec) where

import Domain.AuditLog.Status (Status (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)

spec :: Spec
spec =
  describe "Domain.AuditLog.Status" $ do
    describe "Pending" $ do
      it "supports equality" $ do
        Pending `shouldBe` Pending
        Pending `shouldNotBe` Recorded

      it "supports show" $ do
        show Pending `shouldBe` "Pending"

    describe "Recorded" $ do
      it "supports equality" $ do
        Recorded `shouldBe` Recorded
        Recorded `shouldNotBe` Failed

      it "supports show" $ do
        show Recorded `shouldBe` "Recorded"

    describe "Failed" $ do
      it "supports equality" $ do
        Failed `shouldBe` Failed
        Failed `shouldNotBe` Pending

      it "supports show" $ do
        show Failed `shouldBe` "Failed"

    describe "Ord" $ do
      it "orders constructors by declaration order" $ do
        compare Pending Recorded `shouldBe` LT
        compare Recorded Failed `shouldBe` LT
        compare Failed Pending `shouldBe` GT
        compare Pending Pending `shouldBe` EQ
