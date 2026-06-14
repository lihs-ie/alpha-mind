module Presentation.Handler.ModelValidationsSpec (spec) where

import Data.Aeson (Value, decode)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
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
    }

testApp :: Application
testApp = serve bffApiProxy (bffServer testAppEnv)

viewerWithoutModels :: AuthenticatedUser
viewerWithoutModels =
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

modelsValidationRequest :: Maybe Text -> SRequest
modelsValidationRequest maybeToken =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { Wai.requestMethod = "GET"
            , Wai.requestHeaders =
                [("Accept", "application/json")]
                  <> case maybeToken of
                    Nothing -> []
                    Just tokenText ->
                      [("Authorization", "Bearer " <> encodeUtf8 tokenText)]
            }
          "/models/validation"
    , simpleRequestBody = ""
    }

modelValidationByVersionRequest :: Maybe Text -> SRequest
modelValidationByVersionRequest maybeToken =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { Wai.requestMethod = "GET"
            , Wai.requestHeaders =
                [("Accept", "application/json")]
                  <> case maybeToken of
                    Nothing -> []
                    Just tokenText ->
                      [("Authorization", "Bearer " <> encodeUtf8 tokenText)]
            }
          "/models/validation/v1.0.0"
    , simpleRequestBody = ""
    }

lookupText :: String -> Value -> Maybe Aeson.Value
lookupText key (Aeson.Object obj) = KeyMap.lookup (Key.fromString key) obj
lookupText _ _ = Nothing

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Presentation.Handler.ModelValidations" $ do
  describe "GET /models/validation" $ do
    it "returns 401 when Authorization header is missing" $ do
      response <- runSession (srequest (modelsValidationRequest Nothing)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 401 when Authorization header has invalid token" $ do
      let invalidToken = "invalid.jwt.token" :: Text
      response <- runSession (srequest (modelsValidationRequest (Just invalidToken))) testApp
      simpleStatus response `shouldBe` status401

    it "returns 403 when token lacks models:read permission" $ do
      tokenText <- issueTestToken viewerWithoutModels
      response <- runSession (srequest (modelsValidationRequest (Just tokenText))) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_FORBIDDEN"
            _ -> False
        Nothing -> False

  describe "GET /models/validation/v1.0.0" $ do
    it "returns 401 when Authorization header is missing" $ do
      response <- runSession (srequest (modelValidationByVersionRequest Nothing)) testApp
      simpleStatus response `shouldBe` status401
