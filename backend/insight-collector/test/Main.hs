module Main (main) where

import ACL.ExternalSource.GitHubSpec qualified
import ACL.ExternalSource.PaperSpec qualified
import ACL.ExternalSource.XSpec qualified
import ACL.ExternalSource.YouTubeSpec qualified
import Domain.InsightCollection.AggregateSpec qualified
import Domain.InsightCollection.DomainEventSpec qualified
import Domain.InsightCollection.EvidenceCompletenessPolicySpec qualified
import Domain.InsightCollection.InsightDispatchSpec qualified
import Domain.InsightCollection.ReasonCodeSpec qualified
import Domain.InsightCollection.SourcePolicyComplianceServiceSpec qualified
import Infrastructure.Idempotency.InsightIdempotencySpec qualified
import Infrastructure.Publisher.PubSubInsightEventPublisherSpec qualified
import Infrastructure.Repository.FirestoreInsightRecordRepositorySpec qualified
import Presentation.PubSubHandlerSpec qualified
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
    ACL.ExternalSource.XSpec.spec
    ACL.ExternalSource.YouTubeSpec.spec
    ACL.ExternalSource.PaperSpec.spec
    ACL.ExternalSource.GitHubSpec.spec
    Infrastructure.Repository.FirestoreInsightRecordRepositorySpec.spec
    Infrastructure.Publisher.PubSubInsightEventPublisherSpec.spec
    Infrastructure.Idempotency.InsightIdempotencySpec.spec
    Presentation.PubSubHandlerSpec.spec
