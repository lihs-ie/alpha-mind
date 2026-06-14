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
import Test.Hspec (hspec)

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
