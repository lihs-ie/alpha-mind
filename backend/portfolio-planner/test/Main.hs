module Main (main) where

import Domain.OrderProposal.AggregateSpec qualified
import Domain.OrderProposal.Factory.OrderProposalFactorySpec qualified
import Domain.OrderProposal.Factory.ProposalDispatchFactorySpec qualified
import Domain.OrderProposal.ProposalDispatchSpec qualified
import Domain.OrderProposal.Service.OrderSizingPolicySpec qualified
import Domain.OrderProposal.Service.ProposalEligibilityPolicySpec qualified
import Domain.OrderProposal.Specification.ComplianceReviewGateSpecificationSpec qualified
import Domain.OrderProposal.Specification.ProposalBatchConsistencySpecificationSpec qualified
import Domain.OrderProposal.Specification.SignalIntegritySpecificationSpec qualified
import Infrastructure.Publisher.PubSubPortfolioEventPublisherSpec qualified
import Infrastructure.Repository.FirestoreIdempotencyRepositorySpec qualified
import Infrastructure.Repository.FirestoreOrderProposalRepositorySpec qualified
import Infrastructure.Repository.FirestoreProposalDispatchRepositorySpec qualified
import Test.Hspec (hspec)
import UseCase.PortfolioPlanningServiceSpec qualified
import UseCase.ProposalAuditWriterSpec qualified

main :: IO ()
main =
  hspec $ do
    Domain.OrderProposal.AggregateSpec.spec
    Domain.OrderProposal.ProposalDispatchSpec.spec
    Domain.OrderProposal.Specification.SignalIntegritySpecificationSpec.spec
    Domain.OrderProposal.Specification.ComplianceReviewGateSpecificationSpec.spec
    Domain.OrderProposal.Specification.ProposalBatchConsistencySpecificationSpec.spec
    Domain.OrderProposal.Service.ProposalEligibilityPolicySpec.spec
    Domain.OrderProposal.Service.OrderSizingPolicySpec.spec
    Domain.OrderProposal.Factory.OrderProposalFactorySpec.spec
    Domain.OrderProposal.Factory.ProposalDispatchFactorySpec.spec
    Infrastructure.Publisher.PubSubPortfolioEventPublisherSpec.spec
    Infrastructure.Repository.FirestoreIdempotencyRepositorySpec.spec
    Infrastructure.Repository.FirestoreOrderProposalRepositorySpec.spec
    Infrastructure.Repository.FirestoreProposalDispatchRepositorySpec.spec
    UseCase.PortfolioPlanningServiceSpec.spec
    UseCase.ProposalAuditWriterSpec.spec
