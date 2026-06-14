module Main (main) where

import Domain.OrderExecution.AggregateSpec qualified
import Domain.OrderExecution.BrokerExecutionPolicySpec qualified
import Domain.OrderExecution.DemoRunEvaluationSpec qualified
import Domain.OrderExecution.ExecutionIdempotencyPolicySpec qualified
import Infrastructure.ACL.BrokerTSpec qualified
import Test.Hspec (hspec)
import UseCase.CompleteDemoRunSpec qualified
import UseCase.ExecuteOrderSpec qualified

main :: IO ()
main =
  hspec $ do
    Domain.OrderExecution.AggregateSpec.spec
    Domain.OrderExecution.BrokerExecutionPolicySpec.spec
    Domain.OrderExecution.ExecutionIdempotencyPolicySpec.spec
    Domain.OrderExecution.DemoRunEvaluationSpec.spec
    Infrastructure.ACL.BrokerTSpec.spec
    UseCase.ExecuteOrderSpec.spec
    UseCase.CompleteDemoRunSpec.spec
