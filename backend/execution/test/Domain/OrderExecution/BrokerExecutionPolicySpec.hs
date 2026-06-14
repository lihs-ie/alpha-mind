module Domain.OrderExecution.BrokerExecutionPolicySpec (spec) where

import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Domain.OrderExecution.Aggregate (BrokerOrder (..), FailureDetail (..))
import Domain.OrderExecution.BrokerExecutionPolicy (ClassifiedOutcome (..), classifyOutcome)
import Domain.OrderExecution.BrokerOrderPort (BrokerOutcome (..))
import Domain.OrderExecution.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

spec :: Spec
spec =
  describe "Domain.OrderExecution.BrokerExecutionPolicy.classifyOutcome (Must-15)" $ do
    it "maps an accepted outcome to ClassifiedSuccess with brokerOrder" $ do
      classifyOutcome (BrokerAccepted (BrokerOrder "id-001") fixedTime)
        `shouldBe` ClassifiedSuccess (BrokerOrder "id-001")

    it "maps timeout label to retryable EXECUTION_BROKER_TIMEOUT" $ do
      case classifyOutcome (BrokerRejected "EXECUTION_BROKER_TIMEOUT" Nothing True) of
        ClassifiedFailure failure -> do
          failure.reasonCode `shouldBe` ExecutionBrokerTimeout
          failure.retryable `shouldBe` True
        other -> error ("unexpected: " <> show other)

    it "maps market closed to non-retryable EXECUTION_MARKET_CLOSED" $ do
      case classifyOutcome (BrokerRejected "MARKET_CLOSED" (Just "closed") False) of
        ClassifiedFailure failure -> do
          failure.reasonCode `shouldBe` ExecutionMarketClosed
          failure.retryable `shouldBe` False
          failure.detail `shouldBe` Just "closed"
        other -> error ("unexpected: " <> show other)

    it "maps insufficient funds to non-retryable EXECUTION_INSUFFICIENT_FUNDS" $ do
      case classifyOutcome (BrokerRejected "insufficient_funds" Nothing False) of
        ClassifiedFailure failure -> do
          failure.reasonCode `shouldBe` ExecutionInsufficientFunds
          failure.retryable `shouldBe` False
        other -> error ("unexpected: " <> show other)

    it "maps broker rejected to non-retryable EXECUTION_BROKER_REJECTED" $ do
      case classifyOutcome (BrokerRejected "REJECTED" Nothing False) of
        ClassifiedFailure failure -> do
          failure.reasonCode `shouldBe` ExecutionBrokerRejected
          failure.retryable `shouldBe` False
        other -> error ("unexpected: " <> show other)

    it "maps an unknown error with retryable hint to retryable DEPENDENCY_UNAVAILABLE" $ do
      case classifyOutcome (BrokerRejected "weird-network-blip" Nothing True) of
        ClassifiedFailure failure -> do
          failure.reasonCode `shouldBe` DependencyUnavailable
          failure.retryable `shouldBe` True
        other -> error ("unexpected: " <> show other)

    it "maps an unknown non-retryable error to EXECUTION_BROKER_REJECTED" $ do
      case classifyOutcome (BrokerRejected "weird-business-error" Nothing False) of
        ClassifiedFailure failure -> do
          failure.reasonCode `shouldBe` ExecutionBrokerRejected
          failure.retryable `shouldBe` False
        other -> error ("unexpected: " <> show other)
