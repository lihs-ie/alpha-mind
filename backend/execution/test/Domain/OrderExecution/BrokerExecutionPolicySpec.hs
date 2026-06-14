module Domain.OrderExecution.BrokerExecutionPolicySpec (spec) where

import Domain.OrderExecution.BrokerExecutionPolicy (classifyBrokerError, isRetryable)
import Domain.OrderExecution.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "Domain.OrderExecution.BrokerExecutionPolicy" $ do
    describe "isRetryable" $ do
      it "ExecutionBrokerTimeout is retryable" $
        isRetryable ExecutionBrokerTimeout `shouldBe` True

      it "DependencyTimeout is retryable" $
        isRetryable DependencyTimeout `shouldBe` True

      it "InternalError is retryable" $
        isRetryable InternalError `shouldBe` True

      it "ExecutionBrokerRejected is not retryable" $
        isRetryable ExecutionBrokerRejected `shouldBe` False

      it "ExecutionMarketClosed is not retryable" $
        isRetryable ExecutionMarketClosed `shouldBe` False

      it "ExecutionInsufficientFunds is not retryable" $
        isRetryable ExecutionInsufficientFunds `shouldBe` False

      it "IdempotencyDuplicateEvent is not retryable" $
        isRetryable IdempotencyDuplicateEvent `shouldBe` False

      it "StateConflict is not retryable" $
        isRetryable StateConflict `shouldBe` False

    describe "classifyBrokerError" $ do
      it "maps 'timeout' to ExecutionBrokerTimeout" $
        classifyBrokerError "timeout" `shouldBe` ExecutionBrokerTimeout

      it "maps 'rejected' to ExecutionBrokerRejected" $
        classifyBrokerError "rejected" `shouldBe` ExecutionBrokerRejected

      it "maps 'market_closed' to ExecutionMarketClosed" $
        classifyBrokerError "market_closed" `shouldBe` ExecutionMarketClosed

      it "maps 'insufficient_funds' to ExecutionInsufficientFunds" $
        classifyBrokerError "insufficient_funds" `shouldBe` ExecutionInsufficientFunds

      it "maps unknown errors to InternalError" $
        classifyBrokerError "unknown_error" `shouldBe` InternalError
