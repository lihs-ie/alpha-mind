module Domain.AuditLog.ReasonCodeSpec (spec) where

import Domain.AuditLog.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

spec :: Spec
spec =
  describe "Domain.AuditLog.ReasonCode" $ do
    describe "DataSchemaInvalid" $ do
      it "supports equality" $ do
        DataSchemaInvalid `shouldBe` DataSchemaInvalid
        DataSchemaInvalid `shouldNotBe` AuditWriteFailed

      it "supports show" $ do
        show DataSchemaInvalid `shouldBe` "DataSchemaInvalid"

    describe "AuditWriteFailed" $ do
      it "supports equality" $ do
        AuditWriteFailed `shouldBe` AuditWriteFailed
        AuditWriteFailed `shouldNotBe` IdempotencyDuplicateEvent

      it "supports show" $ do
        show AuditWriteFailed `shouldBe` "AuditWriteFailed"

    describe "IdempotencyDuplicateEvent" $ do
      it "supports equality" $ do
        IdempotencyDuplicateEvent `shouldBe` IdempotencyDuplicateEvent
        IdempotencyDuplicateEvent `shouldNotBe` DataSchemaInvalid

      it "supports show" $ do
        show IdempotencyDuplicateEvent `shouldBe` "IdempotencyDuplicateEvent"

    describe "Ord" $ do
      it "orders constructors by declaration order" $ do
        compare DataSchemaInvalid AuditWriteFailed `shouldBe` LT
        compare AuditWriteFailed IdempotencyDuplicateEvent `shouldBe` LT
        compare IdempotencyDuplicateEvent DataSchemaInvalid `shouldBe` GT
        compare DataSchemaInvalid DataSchemaInvalid `shouldBe` EQ
        [DataSchemaInvalid, IdempotencyDuplicateEvent, AuditWriteFailed]
          `shouldSatisfy` (\xs -> minimum xs == DataSchemaInvalid)
