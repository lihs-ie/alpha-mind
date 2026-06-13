module Domain.AuditLogSpec (spec) where

import Data.ULID (ULID, ulidFromInteger)
import Domain.AuditLog (Trace (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

spec :: Spec
spec =
  describe "Domain.AuditLog" $ do
    describe "Trace" $ do
      it "constructs with a ULID value" $ do
        let trace = Trace (mkULID 1)
        trace.value `shouldBe` mkULID 1

      it "supports equality comparison" $ do
        Trace (mkULID 1) `shouldBe` Trace (mkULID 1)
        Trace (mkULID 1) `shouldNotBe` Trace (mkULID 2)

      it "supports ordering" $ do
        compare (Trace (mkULID 1)) (Trace (mkULID 2)) `shouldBe` LT
        compare (Trace (mkULID 2)) (Trace (mkULID 1)) `shouldBe` GT
        compare (Trace (mkULID 1)) (Trace (mkULID 1)) `shouldBe` EQ

      it "supports show" $ do
        show (Trace (mkULID 1)) `shouldSatisfy` (not . null)
