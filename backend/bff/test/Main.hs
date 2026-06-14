module Main (main) where

import Domain.Auth.CredentialSpec qualified
import Presentation.Handler.AuditSpec qualified
import Presentation.Handler.AuthSpec qualified
import Presentation.Handler.DashboardSpec qualified
import Presentation.Handler.OrdersSpec qualified
import Test.Hspec (hspec)

main :: IO ()
main =
  hspec $ do
    Domain.Auth.CredentialSpec.spec
    Presentation.Handler.AuditSpec.spec
    Presentation.Handler.AuthSpec.spec
    Presentation.Handler.DashboardSpec.spec
    Presentation.Handler.OrdersSpec.spec
