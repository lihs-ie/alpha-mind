module Domain.OrderExecution.ExecutionIdempotencyPolicySpec (spec) where

import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.Aggregate (
  ExecutionRequest (..),
  OrderExecutionIdentifier (..),
  acceptApprovedOrder,
  dispatchToBroker,
  recordBrokerFailure,
  recordBrokerSuccess,
 )
import Domain.OrderExecution.ExecutionIdempotencyPolicy (isDuplicateDispatch)
import Domain.OrderExecution.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

testIdentifier :: OrderExecutionIdentifier
testIdentifier = OrderExecutionIdentifier (mkULID 1)

testTrace :: Trace
testTrace = Trace (mkULID 100)

testRequest :: ExecutionRequest
testRequest =
  ExecutionRequest
    { symbol = "7203.T"
    , side = "BUY"
    , qty = 100
    }

spec :: Spec
spec =
  describe "Domain.OrderExecution.ExecutionIdempotencyPolicy" $ do
    describe "isDuplicateDispatch" $ do
      it "returns False for APPROVED status" $ do
        let (execution, _) = acceptApprovedOrder testIdentifier testRequest testTrace
        isDuplicateDispatch execution `shouldBe` False

      it "returns True for EXECUTED status" $ do
        let (execution, _) = acceptApprovedOrder testIdentifier testRequest testTrace
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right dispatch"
          Right (dispatched, _) ->
            case recordBrokerSuccess "BROKER-001" fixedTime dispatched of
              Left _ -> fail "Expected Right success"
              Right (executed, _) ->
                isDuplicateDispatch executed `shouldBe` True

      it "returns True for FAILED status" $ do
        let (execution, _) = acceptApprovedOrder testIdentifier testRequest testTrace
        case dispatchToBroker fixedTime execution of
          Left _ -> fail "Expected Right dispatch"
          Right (dispatched, _) ->
            case recordBrokerFailure ExecutionBrokerRejected Nothing fixedTime dispatched of
              Left _ -> fail "Expected Right failure"
              Right (failed, _) ->
                isDuplicateDispatch failed `shouldBe` True
