module Main (main) where

import AuthInternalJwtSpec qualified
import BootstrapSpec qualified
import CloudEventSpec qualified
import ConfigEnvSpec qualified
import FirestoreSpec qualified
import HealthSpec qualified
import IdempotencySpec qualified
import MetricsSpec qualified
import PubSubSpec qualified
import ResponseSpec qualified
import RetrySpec qualified
import StorageGCSSpec qualified
import Test.Hspec (hspec)

main :: IO ()
main =
  hspec $ do
    AuthInternalJwtSpec.spec
    BootstrapSpec.spec
    CloudEventSpec.spec
    ConfigEnvSpec.spec
    FirestoreSpec.spec
    HealthSpec.spec
    IdempotencySpec.spec
    MetricsSpec.spec
    PubSubSpec.spec
    ResponseSpec.spec
    RetrySpec.spec
    StorageGCSSpec.spec
