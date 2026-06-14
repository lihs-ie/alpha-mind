module Main (main) where

import Domain.RiskAssessment.AggregateSpec qualified
import Domain.RiskAssessment.ReasonCodeSpec qualified
import Domain.RiskAssessment.Service.RiskScreeningPolicySpec qualified
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
  Domain.RiskAssessment.AggregateSpec.spec
  Domain.RiskAssessment.ReasonCodeSpec.spec
  Domain.RiskAssessment.Service.RiskScreeningPolicySpec.spec
