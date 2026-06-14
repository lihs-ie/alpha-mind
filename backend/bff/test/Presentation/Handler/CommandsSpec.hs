module Presentation.Handler.CommandsSpec (spec) where

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
import Network.HTTP.Types (status401, status403, status503)
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
    }

testApp :: Application
testApp = serve bffApiProxy (bffServer testAppEnv)

-- | Admin user with commands:run permission.
adminWithCommandsRun :: AuthenticatedUser
adminWithCommandsRun =
  AuthenticatedUser
    { identifier = "admin-001"
    , email = EmailAddress "admin@example.com"
    , role = Admin
    , permissions =
        [ AuthPermission "commands:run"
        , AuthPermission "dashboard:read"
        ]
    }

-- | Viewer missing commands:run permission.
viewerWithoutCommandsRun :: AuthenticatedUser
viewerWithoutCommandsRun =
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

runCycleRequest :: Maybe Text -> ByteString -> SRequest
runCycleRequest maybeToken requestBody =
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
          "/commands/run-cycle"
    , simpleRequestBody = requestBody
    }

runInsightCycleRequest :: Maybe Text -> ByteString -> SRequest
runInsightCycleRequest maybeToken requestBody =
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
          "/commands/run-insight-cycle"
    , simpleRequestBody = requestBody
    }

lookupText :: String -> Value -> Maybe Aeson.Value
lookupText key (Aeson.Object obj) = KeyMap.lookup (Key.fromString key) obj
lookupText _ _ = Nothing

emptyBody :: ByteString
emptyBody = encode (object ([] :: [(Aeson.Key, Aeson.Value)]))

insightCycleBody :: ByteString
insightCycleBody =
  encode
    ( object
        [ "mode" .= ("manual" :: Text)
        , "sourceTypes" .= (["x", "youtube"] :: [Text])
        ]
    )

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Presentation.Handler.Commands" $ do
  describe "POST /commands/run-cycle" $ do
    it "returns 401 when Authorization header is missing" $ do
      response <- runSession (srequest (runCycleRequest Nothing emptyBody)) testApp
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
      response <- runSession (srequest (runCycleRequest (Just invalidToken) emptyBody)) testApp
      simpleStatus response `shouldBe` status401
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_INVALID_CREDENTIALS"
            _ -> False
        Nothing -> False

    it "returns 403 when token lacks commands:run permission" $ do
      tokenText <- issueTestToken viewerWithoutCommandsRun
      response <- runSession (srequest (runCycleRequest (Just tokenText) emptyBody)) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_FORBIDDEN"
            _ -> False
        Nothing -> False

    -- Note: with valid token, the handler proceeds to check Firestore for kill-switch state.
    -- Without a real Firestore emulator, this returns 503 DEPENDENCY_UNAVAILABLE, which
    -- verifies the auth gate is passed and the kill-switch check is reached.
    it "returns 503 DEPENDENCY_UNAVAILABLE when Firestore is unreachable (valid token, post-auth)" $ do
      tokenText <- issueTestToken adminWithCommandsRun
      response <- runSession (srequest (runCycleRequest (Just tokenText) emptyBody)) testApp
      simpleStatus response `shouldBe` status503
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "DEPENDENCY_UNAVAILABLE"
            _ -> False
        Nothing -> False

  describe "POST /commands/run-insight-cycle" $ do
    it "returns 401 when Authorization header is missing" $ do
      response <- runSession (srequest (runInsightCycleRequest Nothing insightCycleBody)) testApp
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
      response <- runSession (srequest (runInsightCycleRequest (Just invalidToken) insightCycleBody)) testApp
      simpleStatus response `shouldBe` status401
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_INVALID_CREDENTIALS"
            _ -> False
        Nothing -> False

    it "returns 403 when token lacks commands:run permission" $ do
      tokenText <- issueTestToken viewerWithoutCommandsRun
      response <- runSession (srequest (runInsightCycleRequest (Just tokenText) insightCycleBody)) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_FORBIDDEN"
            _ -> False
        Nothing -> False

    -- Note: with valid token, the handler proceeds to check Firestore for kill-switch state.
    -- Without a real Firestore emulator, this returns 503 DEPENDENCY_UNAVAILABLE, which
    -- verifies the auth gate is passed and the kill-switch check is reached.
    it "returns 503 DEPENDENCY_UNAVAILABLE when Firestore is unreachable (valid token, post-auth)" $ do
      tokenText <- issueTestToken adminWithCommandsRun
      response <- runSession (srequest (runInsightCycleRequest (Just tokenText) insightCycleBody)) testApp
      simpleStatus response `shouldBe` status503
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "DEPENDENCY_UNAVAILABLE"
            _ -> False
        Nothing -> False
