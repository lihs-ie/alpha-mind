module Domain.OrderExecution.SpecificationSpec (spec) where

import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.Aggregate (
  BrokerOrder (..),
  ExecutionRequest (..),
  FailureDetail (..),
  OrderExecution,
  OrderExecutionIdentifier (..),
  OrderSide (..),
  acceptApprovedOrder,
  defaultRetryPolicy,
  recordBrokerSuccess,
 )
import Domain.OrderExecution.ReasonCode (ReasonCode (..))
import Domain.OrderExecution.Specification (
  ApprovedStatusSpecification (..),
  RetryableFailureSpecification (..),
  isApproved,
  isRetryableFailure,
 )
import Test.Hspec (Spec, describe, it, shouldBe)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

testRequest :: ExecutionRequest
testRequest = ExecutionRequest{symbol = "1306.T", side = Buy, qty = 100}

approvedExecution :: OrderExecution
approvedExecution =
  acceptApprovedOrder
    (OrderExecutionIdentifier (mkULID 1))
    testRequest
    defaultRetryPolicy
    (Trace (mkULID 100))

spec :: Spec
spec = do
  describe "ApprovedStatusSpecification.isApproved (Must-17, RULE-EX-001)" $ do
    it "is satisfied by a freshly accepted (Approved) execution" $ do
      isApproved ApprovedStatusSpecification approvedExecution `shouldBe` True

    it "is not satisfied after the execution is executed" $ do
      case recordBrokerSuccess (BrokerOrder "id-001") fixedTime approvedExecution of
        Right (executed, _) -> isApproved ApprovedStatusSpecification executed `shouldBe` False
        Left domainError -> error ("unexpected Left: " <> show domainError)

  describe "RetryableFailureSpecification.isRetryableFailure (Must-17, RULE-EX-003)" $ do
    it "is satisfied when retryable is True" $ do
      isRetryableFailure
        RetryableFailureSpecification
        FailureDetail{reasonCode = ExecutionBrokerTimeout, detail = Nothing, retryable = True}
        `shouldBe` True

    it "is not satisfied when retryable is False" $ do
      isRetryableFailure
        RetryableFailureSpecification
        FailureDetail{reasonCode = ExecutionMarketClosed, detail = Nothing, retryable = False}
        `shouldBe` False
