module Presentation.Handler.AuthSpec (spec) where

import Data.Aeson (Value, decode, object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy (ByteString)
import Infrastructure.JWT.JwtIssuer (JwtIssuerEnv (..))
import Infrastructure.Repository.FirestoreUserRepository (FirestoreUserRepositoryEnv (..))
import Network.HTTP.Types (status200, status401)
import Network.Wai (Application, defaultRequest)
import Network.Wai qualified as Wai
import Network.Wai.Test (SRequest (..), SResponse (..), runSession, setPath, srequest)
import Presentation.Api (bffApiProxy, bffServer)
import Presentation.AppM (AppEnv (..))
import Servant (serve)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testAppEnv :: AppEnv
testAppEnv =
  AppEnv
    { jwtIssuerEnv =
        JwtIssuerEnv
          { secretKey = "test-secret-key-that-is-long-enough-for-hs256"
          , issuerUrl = "https://test.local"
          , audienceUrl = "https://test.local"
          , expirySeconds = 3600
          }
    , userRepositoryEnv =
        FirestoreUserRepositoryEnv
          { adminEmail = "admin@example.com"
          , adminPasswordHash = "correct-password"
          }
    , serviceName = "bff"
    }

testApp :: Application
testApp = serve bffApiProxy (bffServer testAppEnv)

loginRequest :: ByteString -> SRequest
loginRequest body =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { Wai.requestMethod = "POST"
            , Wai.requestHeaders =
                [ ("Content-Type", "application/json")
                , ("Accept", "application/json")
                ]
            }
          "/auth/login"
    , simpleRequestBody = body
    }

loginBody :: Value -> ByteString
loginBody = Aeson.encode

hasKey :: String -> Value -> Bool
hasKey key (Aeson.Object obj) = KeyMap.member (Key.fromString key) obj
hasKey _ _ = False

lookupText :: String -> Value -> Maybe Aeson.Value
lookupText key (Aeson.Object obj) = KeyMap.lookup (Key.fromString key) obj
lookupText _ _ = Nothing

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Presentation.Handler.Auth" $ do
  describe "POST /auth/login" $ do
    it "returns 200 with accessToken on valid credentials" $ do
      let body = loginBody (object ["email" .= ("admin@example.com" :: String), "password" .= ("correct-password" :: String)])
      response <- runSession (srequest (loginRequest body)) testApp
      simpleStatus response `shouldBe` status200
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue -> hasKey "accessToken" bodyValue
        Nothing -> False

    it "returns 401 with AUTH_INVALID_CREDENTIALS on wrong password" $ do
      let body = loginBody (object ["email" .= ("admin@example.com" :: String), "password" .= ("wrong-password" :: String)])
      response <- runSession (srequest (loginRequest body)) testApp
      simpleStatus response `shouldBe` status401
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String code) -> code == "AUTH_INVALID_CREDENTIALS"
            _ -> False
        Nothing -> False

    it "returns 401 with AUTH_INVALID_CREDENTIALS on unknown email" $ do
      let body = loginBody (object ["email" .= ("unknown@example.com" :: String), "password" .= ("some-password" :: String)])
      response <- runSession (srequest (loginRequest body)) testApp
      simpleStatus response `shouldBe` status401
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String code) -> code == "AUTH_INVALID_CREDENTIALS"
            _ -> False
        Nothing -> False

    it "returns 401 on invalid email format" $ do
      let body = loginBody (object ["email" .= ("not-an-email" :: String), "password" .= ("some-password" :: String)])
      response <- runSession (srequest (loginRequest body)) testApp
      simpleStatus response `shouldBe` status401
