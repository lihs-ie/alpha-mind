module Main (main) where

import Domain.InsightCollection.AggregateSpec qualified
import Domain.InsightCollection.DomainEventSpec qualified
import Domain.InsightCollection.EvidenceCompletenessPolicySpec qualified
import Domain.InsightCollection.InsightDispatchSpec qualified
import Domain.InsightCollection.ReasonCodeSpec qualified
import Domain.InsightCollection.SourcePolicyComplianceServiceSpec qualified
import Test.Hspec (hspec)
import UseCase.CollectInsightsSpec qualified

main :: IO ()
main =
  hspec $ do
    Domain.InsightCollection.ReasonCodeSpec.spec
    Domain.InsightCollection.AggregateSpec.spec
    Domain.InsightCollection.InsightDispatchSpec.spec
    Domain.InsightCollection.SourcePolicyComplianceServiceSpec.spec
    Domain.InsightCollection.EvidenceCompletenessPolicySpec.spec
    Domain.InsightCollection.DomainEventSpec.spec
    UseCase.CollectInsightsSpec.spec
