module Main (main) where

import Domain.Auth.CredentialSpec qualified
import Domain.Hypothesis.ActionSpec qualified
import Domain.Insight.ActionSpec qualified
import Domain.Operation.ControlSpec qualified
import Presentation.Handler.AuditSpec qualified
import Presentation.Handler.AuthSpec qualified
import Presentation.Handler.CommandsSpec qualified
import Presentation.Handler.DashboardSpec qualified
import Presentation.Handler.HypothesesActionsSpec qualified
import Presentation.Handler.HypothesesSpec qualified
import Presentation.Handler.InsightsActionsSpec qualified
import Presentation.Handler.InsightsSpec qualified
import Presentation.Handler.ModelValidationsSpec qualified
import Presentation.Handler.OperationsSpec qualified
import Presentation.Handler.OrdersActionsSpec qualified
import Presentation.Handler.OrdersSpec qualified
import Presentation.Handler.SettingsSpec qualified
import Test.Hspec (hspec)

main :: IO ()
main =
  hspec $ do
    Domain.Auth.CredentialSpec.spec
    Domain.Hypothesis.ActionSpec.spec
    Domain.Insight.ActionSpec.spec
    Domain.Operation.ControlSpec.spec
    Presentation.Handler.AuditSpec.spec
    Presentation.Handler.AuthSpec.spec
    Presentation.Handler.CommandsSpec.spec
    Presentation.Handler.DashboardSpec.spec
    Presentation.Handler.HypothesesActionsSpec.spec
    Presentation.Handler.HypothesesSpec.spec
    Presentation.Handler.InsightsActionsSpec.spec
    Presentation.Handler.InsightsSpec.spec
    Presentation.Handler.ModelValidationsSpec.spec
    Presentation.Handler.OperationsSpec.spec
    Presentation.Handler.OrdersActionsSpec.spec
    Presentation.Handler.OrdersSpec.spec
    Presentation.Handler.SettingsSpec.spec
