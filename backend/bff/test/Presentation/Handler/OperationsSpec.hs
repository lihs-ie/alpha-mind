module Presentation.Handler.OperationsSpec (spec) where

import Data.Aeson (Value, decode, encode, object, (.=))
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
import Network.HTTP.Types (status400, status401, status403)
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

-- | Admin user with operations:write permission.
adminWithOperationsWrite :: AuthenticatedUser
adminWithOperationsWrite =
  AuthenticatedUser
    { identifier = "admin-001"
    , email = EmailAddress "admin@example.com"
    , role = Admin
    , permissions =
        [ AuthPermission "operations:write"
        , AuthPermission "dashboard:read"
        ]
    }

-- | Viewer missing operations:write permission.
viewerWithoutOperationsWrite :: AuthenticatedUser
viewerWithoutOperationsWrite =
  AuthenticatedUser
    { identifier = "viewer-001"
    , email = EmailAddress "viewer@example.com"
    , role = Viewer
    , permissions = [AuthPermission "dashboard:read"]
    }

issueTestToken :: AuthenticatedUser -> IO Text
issueTestToken authenticatedUser = do
  tokenResult <- issueToken testJwtIssuerEnv authenticatedUser
  case tokenResult of
    Left errorText -> error ("Failed to issue test token: " <> show errorText)
    Right tokenText -> pure tokenText

runtimeRequest :: Maybe Text -> ByteString -> SRequest
runtimeRequest maybeToken requestBody =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { Wai.requestMethod = "POST"
            , Wai.requestHeaders =
                [ ("Content-Type", "application/json")
                , ("Accept", "application/json")
                ]
                  <> case maybeToken of
                    Nothing -> []
                    Just tokenText ->
                      [("Authorization", "Bearer " <> encodeUtf8 tokenText)]
            }
          "/operations/runtime"
    , simpleRequestBody = requestBody
    }

killSwitchRequest :: Maybe Text -> ByteString -> SRequest
killSwitchRequest maybeToken requestBody =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { Wai.requestMethod = "POST"
            , Wai.requestHeaders =
                [ ("Content-Type", "application/json")
                , ("Accept", "application/json")
                ]
                  <> case maybeToken of
                    Nothing -> []
                    Just tokenText ->
                      [("Authorization", "Bearer " <> encodeUtf8 tokenText)]
            }
          "/operations/kill-switch"
    , simpleRequestBody = requestBody
    }

lookupText :: String -> Value -> Maybe Aeson.Value
lookupText key (Aeson.Object obj) = KeyMap.lookup (Key.fromString key) obj
lookupText _ _ = Nothing

startBody :: ByteString
startBody = encode (object ["action" .= ("START" :: Text)])

invalidActionBody :: ByteString
invalidActionBody = encode (object ["action" .= ("RESTART" :: Text)])

enableKillSwitchBody :: ByteString
enableKillSwitchBody = encode (object ["enabled" .= True])

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Presentation.Handler.Operations" $ do
  describe "POST /operations/runtime" $ do
    it "returns 401 when Authorization header is missing" $ do
      response <- runSession (srequest (runtimeRequest Nothing startBody)) testApp
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
      response <- runSession (srequest (runtimeRequest (Just invalidToken) startBody)) testApp
      simpleStatus response `shouldBe` status401
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_INVALID_CREDENTIALS"
            _ -> False
        Nothing -> False

    it "returns 403 when token lacks operations:write permission" $ do
      tokenText <- issueTestToken viewerWithoutOperationsWrite
      response <- runSession (srequest (runtimeRequest (Just tokenText) startBody)) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_FORBIDDEN"
            _ -> False
        Nothing -> False

    it "returns 400 when action is an invalid value" $ do
      tokenText <- issueTestToken adminWithOperationsWrite
      response <- runSession (srequest (runtimeRequest (Just tokenText) invalidActionBody)) testApp
      simpleStatus response `shouldBe` status400
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "REQUEST_VALIDATION_FAILED"
            _ -> False
        Nothing -> False

  describe "POST /operations/kill-switch" $ do
    it "returns 401 when Authorization header is missing" $ do
      response <- runSession (srequest (killSwitchRequest Nothing enableKillSwitchBody)) testApp
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
      response <- runSession (srequest (killSwitchRequest (Just invalidToken) enableKillSwitchBody)) testApp
      simpleStatus response `shouldBe` status401
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_INVALID_CREDENTIALS"
            _ -> False
        Nothing -> False

    it "returns 403 when token lacks operations:write permission" $ do
      tokenText <- issueTestToken viewerWithoutOperationsWrite
      response <- runSession (srequest (killSwitchRequest (Just tokenText) enableKillSwitchBody)) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_FORBIDDEN"
            _ -> False
        Nothing -> False

    it "returns 400 when enabled field is missing" $ do
      tokenText <- issueTestToken adminWithOperationsWrite
      let missingEnabledBody = encode (object ([] :: [(Aeson.Key, Aeson.Value)]))
      response <- runSession (srequest (killSwitchRequest (Just tokenText) missingEnabledBody)) testApp
      simpleStatus response `shouldBe` status400
