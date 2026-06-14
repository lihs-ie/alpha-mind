module Domain.OrderProposal.Service.OrderSizingPolicySpec (spec) where

import Data.Either (isLeft, isRight)
import Data.Ratio ((%))

import Domain.OrderProposal.Service.OrderSizingPolicy (calculateQuantity)
import Domain.OrderProposal.ValueObjects (StrategySnapshot (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------

testStrategy :: StrategySnapshot
testStrategy =
  StrategySnapshot
    { maxOrderCount = 10
    , maxSingleOrderQty = 1000
    , rebalanceThreshold = 0.05
    }

-- ---------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "Domain.OrderProposal.Service.OrderSizingPolicy" $ do
    describe "calculateQuantity (MUST-16)" $ do
      it "returns qty unchanged when below maxSingleOrderQty" $ do
        calculateQuantity testStrategy 500 `shouldBe` Right 500

      it "caps qty at maxSingleOrderQty when above" $ do
        calculateQuantity testStrategy 2000 `shouldBe` Right 1000

      it "returns maxSingleOrderQty exactly when equal" $ do
        calculateQuantity testStrategy 1000 `shouldBe` Right 1000

      it "rejects qty == 0" $ do
        calculateQuantity testStrategy 0 `shouldSatisfy` isLeft

      it "rejects qty < 0" $ do
        calculateQuantity testStrategy (-500) `shouldSatisfy` isLeft

      it "accepts fractional qty" $ do
        calculateQuantity testStrategy (1 % 2) `shouldSatisfy` isRight

      it "MUST-16: pure function — no IO" $ do
        -- The fact that this compiles without IO proves it's pure
        let result = calculateQuantity testStrategy 100
        result `shouldSatisfy` isRight
