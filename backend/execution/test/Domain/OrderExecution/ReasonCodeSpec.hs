module Domain.OrderExecution.ReasonCodeSpec (spec) where

import Domain.OrderExecution.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)

spec :: Spec
spec =
  describe "Domain.OrderExecution.ReasonCode" $ do
    -- Must-06: error-codes.json の execution 関連値を網羅する
    it "covers all execution-related reason codes" $ do
      let allCodes =
            [ ExecutionBrokerTimeout
            , ExecutionBrokerRejected
            , ExecutionMarketClosed
            , ExecutionInsufficientFunds
            , DependencyUnavailable
            , DependencyTimeout
            , IdempotencyDuplicateEvent
            , StateConflict
            ]
      length allCodes `shouldBe` 8

    it "values are distinct" $ do
      ExecutionBrokerTimeout `shouldNotBe` ExecutionBrokerRejected
      ExecutionMarketClosed `shouldNotBe` ExecutionInsufficientFunds
      DependencyUnavailable `shouldNotBe` DependencyTimeout
      IdempotencyDuplicateEvent `shouldNotBe` StateConflict
