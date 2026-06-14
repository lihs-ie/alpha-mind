module Main (main) where

import Domain.Auth.CredentialSpec qualified
import Presentation.Handler.AuthSpec qualified
import Test.Hspec (hspec)

main :: IO ()
main =
  hspec $ do
    Domain.Auth.CredentialSpec.spec
    Presentation.Handler.AuthSpec.spec
