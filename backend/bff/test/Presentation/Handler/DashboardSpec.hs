module Presentation.Handler.DashboardSpec (spec) where

import Data.Aeson (Value, decode)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy (ByteString)
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import Domain.Auth.Credential (
  AuthPermission (..),
  AuthenticatedUser (..),
  EmailAddress (..),
  UserRole (..),
 )
import Infrastructure.JWT.JwtIssuer (JwtIssuerEnv (..), issueToken)
import Infrastructure.Repository.FirestoreUserRepository (FirestoreUserRepositoryEnv (..))
import Messaging.PubSub (PubSubPublisher (..))
import Network.HTTP.Types (status401, status403)
import Network.Wai (Application, defaultRequest)
import Network.Wai qualified as Wai
import Network.Wai.Test (SRequest (..), SResponse (..), runSession, setPath, srequest)
import Persistence.Firestore (FirestoreContext (..))
import Presentation.Api (bffApiProxy, bffServer)
import Presentation.AppM (AppEnv (..))
import Servant (serve)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testJwtIssuerEnv :: JwtIssuerEnv
testJwtIssuerEnv =
  JwtIssuerEnv
    { secretKey = "test-secret-key-that-is-long-enough-for-hs256"
    , issuerUrl = "https://test.local"
    , audienceUrl = "https://test.local"
    , expirySeconds = 3600
    }

testPubSubPublisher :: PubSubPublisher
testPubSubPublisher =
  PubSubPublisher
    { manager = error "PubSub manager not used in tests"
    , projectId = "test-project"
    , baseURL = "https://pubsub.googleapis.com/v1/"
    , accessToken = pure ""
    }

testAppEnv :: AppEnv
testAppEnv =
  AppEnv
    { jwtIssuerEnv = testJwtIssuerEnv
    , userRepositoryEnv =
        FirestoreUserRepositoryEnv
          { adminEmail = "admin@example.com"
          , adminPasswordHash = "correct-password"
          }
    , firestoreContext =
        FirestoreContext
          { projectId = "test-project"
          , databaseId = "(default)"
          }
    , serviceName = "bff"
    , pubSubPublisher = testPubSubPublisher
    , killSwitchTopicName = "test-kill-switch-topic"
    , marketCollectTopicName = "test-market-collect-topic"
    , insightCollectTopicName = "test-insight-collect-topic"
    , ordersApprovedTopicName = "test-orders-approved-topic"
    , ordersRejectedTopicName = "test-orders-rejected-topic"
    , ordersProposedTopicName = "test-orders-proposed-topic"
    , hypothesisProposedTopicName = "test-hypothesis-proposed-topic"
    }

testApp :: Application
testApp = serve bffApiProxy (bffServer testAppEnv)

-- | Admin user with dashboard:read permission.
adminUserWithDashboard :: AuthenticatedUser
adminUserWithDashboard =
  AuthenticatedUser
    { identifier = "admin-001"
    , email = EmailAddress "admin@example.com"
    , role = Admin
    , permissions =
        [ AuthPermission "dashboard:read"
        , AuthPermission "orders:read"
        ]
    }

-- | User missing dashboard:read permission.
viewerUserWithoutDashboard :: AuthenticatedUser
viewerUserWithoutDashboard =
  AuthenticatedUser
    { identifier = "viewer-001"
    , email = EmailAddress "viewer@example.com"
    , role = Viewer
    , permissions = [AuthPermission "orders:read"]
    }

issueTestToken :: AuthenticatedUser -> IO Text
issueTestToken authenticatedUser = do
  tokenResult <- issueToken testJwtIssuerEnv authenticatedUser
  case tokenResult of
    Left errorText -> error ("Failed to issue test token: " <> show errorText)
    Right tokenText -> pure tokenText

dashboardRequest :: Maybe Text -> SRequest
dashboardRequest maybeToken =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { Wai.requestMethod = "GET"
            , Wai.requestHeaders =
                [ ("Accept", "application/json")
                ]
                  <> case maybeToken of
                    Nothing -> []
                    Just tokenText ->
                      [("Authorization", "Bearer " <> encodeUtf8 tokenText)]
            }
          "/dashboard/summary"
    , simpleRequestBody = ""
    }

lookupText :: String -> Value -> Maybe Aeson.Value
lookupText key (Aeson.Object obj) = KeyMap.lookup (Key.fromString key) obj
lookupText _ _ = Nothing

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Presentation.Handler.Dashboard" $ do
  describe "GET /dashboard/summary" $ do
    it "returns 401 when Authorization header is missing" $ do
      response <- runSession (srequest (dashboardRequest Nothing)) testApp
      simpleStatus response `shouldBe` status401
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_INVALID_CREDENTIALS"
            _ -> False
        Nothing -> False

    it "returns 401 when Authorization header has invalid token" $ do
      let invalidToken = "this.is.not.a.valid.jwt" :: Text
      response <- runSession (srequest (dashboardRequest (Just invalidToken))) testApp
      simpleStatus response `shouldBe` status401
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_INVALID_CREDENTIALS"
            _ -> False
        Nothing -> False

    it "returns 403 when token lacks dashboard:read permission" $ do
      tokenText <- issueTestToken viewerUserWithoutDashboard
      response <- runSession (srequest (dashboardRequest (Just tokenText))) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_FORBIDDEN"
            _ -> False
        Nothing -> False
