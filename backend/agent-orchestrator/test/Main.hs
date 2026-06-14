module Main (main) where

import Domain.HypothesisOrchestration.AggregateSpec qualified
import Domain.HypothesisOrchestration.DuplicateThresholdSpecificationSpec qualified
import Domain.HypothesisOrchestration.GenerationContextResolutionPolicySpec qualified
import Domain.HypothesisOrchestration.NonRetryableReasonSpecificationSpec qualified
import Domain.HypothesisOrchestration.OrchestrationDispatchSpec qualified
import Domain.HypothesisOrchestration.ReasonCodeSpec qualified
import Domain.HypothesisOrchestration.ValueObjectsSpec qualified
import Test.Hspec (hspec)
import UseCase.HypothesisOrchestration.DispatchServiceSpec qualified
import UseCase.HypothesisOrchestration.FailureKnowledgeRegistrarSpec qualified
import UseCase.HypothesisOrchestration.HypothesisOrchestrationServiceSpec qualified

main :: IO ()
main =
  hspec $ do
    Domain.HypothesisOrchestration.ReasonCodeSpec.spec
    Domain.HypothesisOrchestration.ValueObjectsSpec.spec
    Domain.HypothesisOrchestration.AggregateSpec.spec
    Domain.HypothesisOrchestration.OrchestrationDispatchSpec.spec
    Domain.HypothesisOrchestration.GenerationContextResolutionPolicySpec.spec
    Domain.HypothesisOrchestration.DuplicateThresholdSpecificationSpec.spec
    Domain.HypothesisOrchestration.NonRetryableReasonSpecificationSpec.spec
    UseCase.HypothesisOrchestration.DispatchServiceSpec.spec
    UseCase.HypothesisOrchestration.FailureKnowledgeRegistrarSpec.spec
    UseCase.HypothesisOrchestration.HypothesisOrchestrationServiceSpec.spec
