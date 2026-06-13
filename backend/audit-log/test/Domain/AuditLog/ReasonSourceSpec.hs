module Domain.AuditLog.ReasonSourceSpec (spec) where

import Domain.AuditLog.ReasonSource (ReasonSource (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)

spec :: Spec
spec =
  describe "Domain.AuditLog.ReasonSource" $ do
    describe "FromReasonCode" $ do
      it "supports equality" $ do
        FromReasonCode `shouldBe` FromReasonCode
        FromReasonCode `shouldNotBe` FromActionReasonCode

      it "supports show" $ do
        show FromReasonCode `shouldBe` "FromReasonCode"

    describe "FromActionReasonCode" $ do
      it "supports equality" $ do
        FromActionReasonCode `shouldBe` FromActionReasonCode
        FromActionReasonCode `shouldNotBe` FromReason

      it "supports show" $ do
        show FromActionReasonCode `shouldBe` "FromActionReasonCode"

    describe "FromReason" $ do
      it "supports equality" $ do
        FromReason `shouldBe` FromReason
        FromReason `shouldNotBe` FromNone

      it "supports show" $ do
        show FromReason `shouldBe` "FromReason"

    describe "FromNone" $ do
      it "supports equality" $ do
        FromNone `shouldBe` FromNone
        FromNone `shouldNotBe` FromReasonCode

      it "supports show" $ do
        show FromNone `shouldBe` "FromNone"

    describe "Ord" $ do
      it "orders constructors by declaration order" $ do
        compare FromReasonCode FromActionReasonCode `shouldBe` LT
        compare FromActionReasonCode FromReason `shouldBe` LT
        compare FromReason FromNone `shouldBe` LT
        compare FromNone FromReasonCode `shouldBe` GT
        compare FromNone FromNone `shouldBe` EQ
