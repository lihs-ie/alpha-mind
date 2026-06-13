module Domain.MarketCollectionSpec (spec) where

import Data.ULID (ULID, ulidFromInteger)
import Domain.MarketCollection (Trace (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

spec :: Spec
spec =
  describe "Domain.MarketCollection" $ do
    describe "Trace" $ do
      it "supports equality" $ do
        Trace (mkULID 1) `shouldBe` Trace (mkULID 1)
        Trace (mkULID 1) `shouldNotBe` Trace (mkULID 2)

      it "supports ordering" $ do
        compare (Trace (mkULID 1)) (Trace (mkULID 2)) `shouldBe` LT
