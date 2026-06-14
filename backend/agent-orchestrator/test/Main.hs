module Main (main) where

import Domain.HypothesisOrchestration.AggregateSpec qualified
import Domain.HypothesisOrchestration.DuplicateThresholdSpecificationSpec qualified
import Domain.HypothesisOrchestration.GenerationContextResolutionPolicySpec qualified
import Domain.HypothesisOrchestration.NonRetryableReasonSpecificationSpec qualified
import Domain.HypothesisOrchestration.OrchestrationDispatchSpec qualified
import Domain.HypothesisOrchestration.ReasonCodeSpec qualified
import Domain.HypothesisOrchestration.ValueObjectsSpec qualified
import Infrastructure.ACL.SkillExecutorTSpec qualified
import Infrastructure.Firestore.CodeReferenceTemplateRepositorySpec qualified
import Infrastructure.Firestore.FailureKnowledgeRepositorySpec qualified
import Infrastructure.Firestore.HypothesisProposalRepositorySpec qualified
import Infrastructure.Firestore.InstructionProfileRepositorySpec qualified
import Infrastructure.Firestore.OrchestrationDispatchRepositorySpec qualified
import Infrastructure.Firestore.SkillRegistryRepositorySpec qualified
import Infrastructure.PubSub.HypothesisEventPublisherSpec qualified
import Presentation.PubSubHandlerSpec qualified
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
    Infrastructure.ACL.SkillExecutorTSpec.spec
    Infrastructure.Firestore.SkillRegistryRepositorySpec.spec
    Infrastructure.Firestore.InstructionProfileRepositorySpec.spec
    Infrastructure.Firestore.CodeReferenceTemplateRepositorySpec.spec
    Infrastructure.Firestore.FailureKnowledgeRepositorySpec.spec
    Infrastructure.Firestore.HypothesisProposalRepositorySpec.spec
    Infrastructure.Firestore.OrchestrationDispatchRepositorySpec.spec
    Infrastructure.PubSub.HypothesisEventPublisherSpec.spec
    Presentation.PubSubHandlerSpec.spec
    UseCase.HypothesisOrchestration.DispatchServiceSpec.spec
    UseCase.HypothesisOrchestration.FailureKnowledgeRegistrarSpec.spec
    UseCase.HypothesisOrchestration.HypothesisOrchestrationServiceSpec.spec
