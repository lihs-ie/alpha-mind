{-# OPTIONS_GHC -fno-hpc #-}

{- | Tests for 'Presentation.Api' (RiskGuardServer).

 TST-PRES-004: GET /healthz returns 200 with @{"status":"ok"}@.
 TST-PRES-005: POST /internal/orders/{id}/approve returns 400 for invalid ULID.

 Uses hspec-wai for HTTP-level testing against the Servant application.
 Test doubles live in this file only. No mock code enters src/.
-}
module Presentation.Server.RiskGuardServerSpec (spec) where

import Data.Aeson (encode, object, (.=))
import Data.ByteString qualified as ByteString
import Data.CaseInsensitive qualified as CaseInsensitive
import Data.Text (Text)
import Infrastructure.Publisher.PubSubRiskEventPublisher (PubSubRiskEventPublisherEnv (..))
import Infrastructure.Repository.FirestoreIdempotencyKeyRepository (FirestoreIdempotencyKeyEnv (..))
import Infrastructure.Repository.FirestoreKillSwitchStateRepository (FirestoreKillSwitchStateEnv (..))
import Infrastructure.Repository.FirestoreRiskAssessmentRepository (FirestoreRiskAssessmentEnv (..))
import Infrastructure.Repository.FirestoreRiskSettingsRepository (FirestoreRiskSettingsEnv (..))
import Messaging.PubSub (PubSubPublisher (..))
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Network.Wai (Application)
import Persistence.Firestore (FirestoreContext (..))
import Presentation.Api (riskGuardApiProxy, riskGuardServer)
import Presentation.AppM (AppEnv (..))
import Servant (serve)
import Test.Hspec (Spec, describe, it)
import Test.Hspec.Wai (
  ResponseMatcher (..),
  get,
  matchStatus,
  request,
  shouldRespondWith,
  with,
 )

-- ---------------------------------------------------------------------------
-- Test AppEnv
-- ---------------------------------------------------------------------------

makeTestApp :: IO Application
makeTestApp = do
  httpManager <- newManager defaultManagerSettings
  let firestoreCtx =
        FirestoreContext
          { projectId = "test-project"
          , databaseId = "(default)"
          }
      publisher =
        PubSubPublisher
          { manager = httpManager
          , projectId = "test-project"
          , baseURL = "http://localhost:19999/"
          , accessToken = pure "test-token"
          }
      appEnv =
        AppEnv
          { assessmentEnv = FirestoreRiskAssessmentEnv{firestoreContext = firestoreCtx}
          , idempotencyEnv = FirestoreIdempotencyKeyEnv{firestoreContext = firestoreCtx}
          , settingsEnv = FirestoreRiskSettingsEnv{firestoreContext = firestoreCtx}
          , killSwitchEnv = FirestoreKillSwitchStateEnv{firestoreContext = firestoreCtx}
          , publisherEnv =
              PubSubRiskEventPublisherEnv
                { publisher = publisher
                , approvedTopicName = "orders.approved"
                , rejectedTopicName = "orders.rejected"
                }
          , serviceName = "risk-guard"
          }
  pure (serve riskGuardApiProxy (riskGuardServer appEnv))

-- | JSON content-type header.
jsonContentType :: (CaseInsensitive.CI ByteString.ByteString, ByteString.ByteString)
jsonContentType = (CaseInsensitive.mk "Content-Type", "application/json")

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
  with makeTestApp $ do
    describe "TST-PRES-004: GET /healthz returns 200 with {\"status\":\"ok\"}" $ do
      it "returns HTTP 200" $
        get "/healthz"
          `shouldRespondWith` 200

      it "returns JSON body with status=ok" $
        get "/healthz"
          `shouldRespondWith` "{\"status\":\"ok\"}"
            { matchStatus = 200
            }

    describe "TST-PRES-005: POST /internal/orders/{id}/approve" $ do
      it "returns HTTP 400 for invalid ULID identifier (not a valid ULID)" $ do
        let body = encode (object ["actionReasonCode" .= ("manual_approval" :: Text)])
        request "POST" "/internal/orders/not-a-valid-ulid/approve" [jsonContentType] body
          `shouldRespondWith` 400
