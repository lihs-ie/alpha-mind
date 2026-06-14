module Main (main) where

import Domain.RiskAssessment.AggregateSpec qualified
import Domain.RiskAssessment.ReasonCodeSpec qualified
import Domain.RiskAssessment.Service.RiskScreeningPolicySpec qualified
import Infrastructure.Publisher.PubSubRiskEventPublisherSpec qualified
import Infrastructure.Repository.FirestoreIdempotencyKeyRepositorySpec qualified
import Infrastructure.Repository.FirestoreRiskAssessmentRepositorySpec qualified
import Presentation.Server.RiskGuardServerSpec qualified
import Presentation.Subscriber.PubSubOrderRiskSubscriberSpec qualified
import Test.Hspec (hspec)
import UseCase.CheckOrderRiskSpec qualified
import UseCase.SyncKillSwitchSpec qualified

main :: IO ()
main = hspec $ do
  Domain.RiskAssessment.AggregateSpec.spec
  Domain.RiskAssessment.ReasonCodeSpec.spec
  Domain.RiskAssessment.Service.RiskScreeningPolicySpec.spec
  Infrastructure.Publisher.PubSubRiskEventPublisherSpec.spec
  Infrastructure.Repository.FirestoreIdempotencyKeyRepositorySpec.spec
  Infrastructure.Repository.FirestoreRiskAssessmentRepositorySpec.spec
  Presentation.Server.RiskGuardServerSpec.spec
  Presentation.Subscriber.PubSubOrderRiskSubscriberSpec.spec
  UseCase.CheckOrderRiskSpec.spec
  UseCase.SyncKillSwitchSpec.spec
