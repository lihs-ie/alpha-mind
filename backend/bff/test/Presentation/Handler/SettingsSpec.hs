module Presentation.Handler.SettingsSpec (spec) where

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
import Network.HTTP.Types (status400, status401, status403, status503)
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

viewerWithoutSettings :: AuthenticatedUser
viewerWithoutSettings =
  AuthenticatedUser
    { identifier = "viewer-001"
    , email = EmailAddress "viewer@example.com"
    , role = Viewer
    , permissions = [AuthPermission "dashboard:read"]
    }

-- | Admin user with settings:write permission.
adminWithSettingsWrite :: AuthenticatedUser
adminWithSettingsWrite =
  AuthenticatedUser
    { identifier = "admin-001"
    , email = EmailAddress "admin@example.com"
    , role = Admin
    , permissions =
        [ AuthPermission "settings:write"
        , AuthPermission "settings:read"
        ]
    }

-- | Admin user with compliance:write permission.
adminWithComplianceWrite :: AuthenticatedUser
adminWithComplianceWrite =
  AuthenticatedUser
    { identifier = "admin-002"
    , email = EmailAddress "admin@example.com"
    , role = Admin
    , permissions =
        [ AuthPermission "compliance:write"
        , AuthPermission "compliance:read"
        ]
    }

issueTestToken :: AuthenticatedUser -> IO Text
issueTestToken authenticatedUser = do
  tokenResult <- issueToken testJwtIssuerEnv authenticatedUser
  case tokenResult of
    Left errorText -> error ("Failed to issue test token: " <> show errorText)
    Right tokenText -> pure tokenText

settingsRequest :: Maybe Text -> SRequest
settingsRequest maybeToken =
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
          "/settings/strategy"
    , simpleRequestBody = ""
    }

complianceRequest :: Maybe Text -> SRequest
complianceRequest maybeToken =
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
          "/compliance/controls"
    , simpleRequestBody = ""
    }

putSettingsRequest :: Maybe Text -> ByteString -> SRequest
putSettingsRequest maybeToken requestBody =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { Wai.requestMethod = "PUT"
            , Wai.requestHeaders =
                [ ("Content-Type", "application/json")
                , ("Accept", "application/json")
                ]
                  <> case maybeToken of
                    Nothing -> []
                    Just tokenText ->
                      [("Authorization", "Bearer " <> encodeUtf8 tokenText)]
            }
          "/settings/strategy"
    , simpleRequestBody = requestBody
    }

putComplianceRequest :: Maybe Text -> ByteString -> SRequest
putComplianceRequest maybeToken requestBody =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { Wai.requestMethod = "PUT"
            , Wai.requestHeaders =
                [ ("Content-Type", "application/json")
                , ("Accept", "application/json")
                ]
                  <> case maybeToken of
                    Nothing -> []
                    Just tokenText ->
                      [("Authorization", "Bearer " <> encodeUtf8 tokenText)]
            }
          "/compliance/controls"
    , simpleRequestBody = requestBody
    }

lookupText :: String -> Value -> Maybe Aeson.Value
lookupText key (Aeson.Object obj) = KeyMap.lookup (Key.fromString key) obj
lookupText _ _ = Nothing

validStrategyBody :: ByteString
validStrategyBody =
  encode $
    object
      [ "market" .= ("JP" :: Text)
      , "rebalanceFrequency" .= ("daily" :: Text)
      , "symbols" .= (["1306.T"] :: [Text])
      , "dailyLossLimit" .= (5.0 :: Double)
      , "positionConcentrationLimit" .= (20.0 :: Double)
      , "dailyOrderLimit" .= (10 :: Int)
      ]

validComplianceBody :: ByteString
validComplianceBody =
  encode $
    object
      [ "restrictedSymbols" .= ([] :: [Text])
      , "partnerRestrictedSymbols" .= ([] :: [Text])
      , "maxCommentLength" .= (120 :: Int)
      , "autoPromotionEnabled" .= False
      ]

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Presentation.Handler.Settings" $ do
  describe "GET /settings/strategy" $ do
    it "returns 401 when Authorization header is missing" $ do
      response <- runSession (srequest (settingsRequest Nothing)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 403 when token lacks settings:read permission" $ do
      tokenText <- issueTestToken viewerWithoutSettings
      response <- runSession (srequest (settingsRequest (Just tokenText))) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_FORBIDDEN"
            _ -> False
        Nothing -> False

  describe "PUT /settings/strategy" $ do
    it "returns 401 when Authorization header is missing" $ do
      response <- runSession (srequest (putSettingsRequest Nothing validStrategyBody)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 401 when Authorization header has invalid token" $ do
      let invalidToken = "this.is.not.a.valid.jwt" :: Text
      response <- runSession (srequest (putSettingsRequest (Just invalidToken) validStrategyBody)) testApp
      simpleStatus response `shouldBe` status401
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_INVALID_CREDENTIALS"
            _ -> False
        Nothing -> False

    it "returns 403 when token lacks settings:write permission" $ do
      tokenText <- issueTestToken viewerWithoutSettings
      response <- runSession (srequest (putSettingsRequest (Just tokenText) validStrategyBody)) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_FORBIDDEN"
            _ -> False
        Nothing -> False

    it "returns 400 when market is not JP" $ do
      tokenText <- issueTestToken adminWithSettingsWrite
      let invalidMarketBody =
            encode $
              object
                [ "market" .= ("US" :: Text)
                , "rebalanceFrequency" .= ("daily" :: Text)
                , "symbols" .= (["1306.T"] :: [Text])
                , "dailyLossLimit" .= (5.0 :: Double)
                , "positionConcentrationLimit" .= (20.0 :: Double)
                , "dailyOrderLimit" .= (10 :: Int)
                ]
      response <- runSession (srequest (putSettingsRequest (Just tokenText) invalidMarketBody)) testApp
      simpleStatus response `shouldBe` status400
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "REQUEST_VALIDATION_FAILED"
            _ -> False
        Nothing -> False

    it "returns 400 when rebalanceFrequency is invalid" $ do
      tokenText <- issueTestToken adminWithSettingsWrite
      let invalidFrequencyBody =
            encode $
              object
                [ "market" .= ("JP" :: Text)
                , "rebalanceFrequency" .= ("hourly" :: Text)
                , "symbols" .= (["1306.T"] :: [Text])
                , "dailyLossLimit" .= (5.0 :: Double)
                , "positionConcentrationLimit" .= (20.0 :: Double)
                , "dailyOrderLimit" .= (10 :: Int)
                ]
      response <- runSession (srequest (putSettingsRequest (Just tokenText) invalidFrequencyBody)) testApp
      simpleStatus response `shouldBe` status400
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "REQUEST_VALIDATION_FAILED"
            _ -> False
        Nothing -> False

    it "returns 400 when symbols is empty" $ do
      tokenText <- issueTestToken adminWithSettingsWrite
      let emptySymbolsBody =
            encode $
              object
                [ "market" .= ("JP" :: Text)
                , "rebalanceFrequency" .= ("daily" :: Text)
                , "symbols" .= ([] :: [Text])
                , "dailyLossLimit" .= (5.0 :: Double)
                , "positionConcentrationLimit" .= (20.0 :: Double)
                , "dailyOrderLimit" .= (10 :: Int)
                ]
      response <- runSession (srequest (putSettingsRequest (Just tokenText) emptySymbolsBody)) testApp
      simpleStatus response `shouldBe` status400
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "REQUEST_VALIDATION_FAILED"
            _ -> False
        Nothing -> False

    it "returns 503 DEPENDENCY_UNAVAILABLE when Firestore is unreachable (valid token, post-auth)" $ do
      tokenText <- issueTestToken adminWithSettingsWrite
      response <- runSession (srequest (putSettingsRequest (Just tokenText) validStrategyBody)) testApp
      simpleStatus response `shouldBe` status503
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "DEPENDENCY_UNAVAILABLE"
            _ -> False
        Nothing -> False

  describe "GET /compliance/controls" $ do
    it "returns 401 when Authorization header is missing" $ do
      response <- runSession (srequest (complianceRequest Nothing)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 403 when token lacks compliance:read permission" $ do
      tokenText <- issueTestToken viewerWithoutSettings
      response <- runSession (srequest (complianceRequest (Just tokenText))) testApp
      simpleStatus response `shouldBe` status403

  describe "PUT /compliance/controls" $ do
    it "returns 401 when Authorization header is missing" $ do
      response <- runSession (srequest (putComplianceRequest Nothing validComplianceBody)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 401 when Authorization header has invalid token" $ do
      let invalidToken = "this.is.not.a.valid.jwt" :: Text
      response <- runSession (srequest (putComplianceRequest (Just invalidToken) validComplianceBody)) testApp
      simpleStatus response `shouldBe` status401
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_INVALID_CREDENTIALS"
            _ -> False
        Nothing -> False

    it "returns 403 when token lacks compliance:write permission" $ do
      tokenText <- issueTestToken viewerWithoutSettings
      response <- runSession (srequest (putComplianceRequest (Just tokenText) validComplianceBody)) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "AUTH_FORBIDDEN"
            _ -> False
        Nothing -> False

    it "returns 400 when maxCommentLength is below minimum" $ do
      tokenText <- issueTestToken adminWithComplianceWrite
      let invalidBody =
            encode $
              object
                [ "restrictedSymbols" .= ([] :: [Text])
                , "partnerRestrictedSymbols" .= ([] :: [Text])
                , "maxCommentLength" .= (10 :: Int)
                , "autoPromotionEnabled" .= False
                ]
      response <- runSession (srequest (putComplianceRequest (Just tokenText) invalidBody)) testApp
      simpleStatus response `shouldBe` status400
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "REQUEST_VALIDATION_FAILED"
            _ -> False
        Nothing -> False

    it "returns 400 when maxCommentLength exceeds maximum" $ do
      tokenText <- issueTestToken adminWithComplianceWrite
      let invalidBody =
            encode $
              object
                [ "restrictedSymbols" .= ([] :: [Text])
                , "partnerRestrictedSymbols" .= ([] :: [Text])
                , "maxCommentLength" .= (500 :: Int)
                , "autoPromotionEnabled" .= False
                ]
      response <- runSession (srequest (putComplianceRequest (Just tokenText) invalidBody)) testApp
      simpleStatus response `shouldBe` status400
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "REQUEST_VALIDATION_FAILED"
            _ -> False
        Nothing -> False

    it "returns 503 DEPENDENCY_UNAVAILABLE when Firestore is unreachable (valid token, post-auth)" $ do
      tokenText <- issueTestToken adminWithComplianceWrite
      response <- runSession (srequest (putComplianceRequest (Just tokenText) validComplianceBody)) testApp
      simpleStatus response `shouldBe` status503
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue ->
          case lookupText "reasonCode" bodyValue of
            Just (Aeson.String reasonCode) -> reasonCode == "DEPENDENCY_UNAVAILABLE"
            _ -> False
        Nothing -> False
