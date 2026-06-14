module Presentation.Handler.InsightsActionsSpec (spec) where

import Data.Aeson (Value, decode, encode, object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as LazyByteString
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
import Network.HTTP.Types (status401, status403, status422)
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

-- | Admin user with insights:write permission.
adminWithInsightsWrite :: AuthenticatedUser
adminWithInsightsWrite =
  AuthenticatedUser
    { identifier = "admin-001"
    , email = EmailAddress "admin@example.com"
    , role = Admin
    , permissions =
        [ AuthPermission "insights:read"
        , AuthPermission "insights:write"
        ]
    }

-- | Viewer without insights write permission.
viewerWithoutInsightsWrite :: AuthenticatedUser
viewerWithoutInsightsWrite =
  AuthenticatedUser
    { identifier = "viewer-001"
    , email = EmailAddress "viewer@example.com"
    , role = Viewer
    , permissions = [AuthPermission "insights:read"]
    }

issueTestToken :: AuthenticatedUser -> IO Text
issueTestToken authenticatedUser = do
  tokenResult <- issueToken testJwtIssuerEnv authenticatedUser
  case tokenResult of
    Left errorText -> error ("Failed to issue test token: " <> show errorText)
    Right tokenText -> pure tokenText

adoptRequest :: Maybe Text -> ByteString -> SRequest
adoptRequest maybeToken body =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { Wai.requestMethod = "POST"
            , Wai.requestHeaders =
                [("Content-Type", "application/json"), ("Accept", "application/json")]
                  <> case maybeToken of
                    Nothing -> []
                    Just tokenText ->
                      [("Authorization", "Bearer " <> encodeUtf8 tokenText)]
            }
          "/insights/01ARZ3NDEKTSV4RRFFQ69G5FAV/adopt"
    , simpleRequestBody = body
    }

rejectRequest :: Maybe Text -> ByteString -> SRequest
rejectRequest maybeToken body =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { Wai.requestMethod = "POST"
            , Wai.requestHeaders =
                [("Content-Type", "application/json"), ("Accept", "application/json")]
                  <> case maybeToken of
                    Nothing -> []
                    Just tokenText ->
                      [("Authorization", "Bearer " <> encodeUtf8 tokenText)]
            }
          "/insights/01ARZ3NDEKTSV4RRFFQ69G5FAV/reject"
    , simpleRequestBody = body
    }

hypothesizeRequest :: Maybe Text -> ByteString -> SRequest
hypothesizeRequest maybeToken body =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { Wai.requestMethod = "POST"
            , Wai.requestHeaders =
                [("Content-Type", "application/json"), ("Accept", "application/json")]
                  <> case maybeToken of
                    Nothing -> []
                    Just tokenText ->
                      [("Authorization", "Bearer " <> encodeUtf8 tokenText)]
            }
          "/insights/01ARZ3NDEKTSV4RRFFQ69G5FAV/hypothesize"
    , simpleRequestBody = body
    }

lookupValue :: String -> Value -> Maybe Aeson.Value
lookupValue key (Aeson.Object obj) = KeyMap.lookup (Key.fromString key) obj
lookupValue _ _ = Nothing

hasReasonCode :: Text -> Value -> Bool
hasReasonCode expectedCode bodyValue =
  case lookupValue "reasonCode" bodyValue of
    Just (Aeson.String reasonCodeText) -> reasonCodeText == expectedCode
    _ -> False

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Presentation.Handler.Insights (action endpoints)" $ do
  describe "POST /insights/{identifier}/adopt" $ do
    it "returns 401 when Authorization header is missing" $ do
      let body = encode (object ["actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
      response <- runSession (srequest (adoptRequest Nothing body)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 401 when Authorization header has invalid token" $ do
      let body = encode (object ["actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
      response <- runSession (srequest (adoptRequest (Just "invalid.jwt.token") body)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 403 when token lacks insights:write permission" $ do
      tokenText <- issueTestToken viewerWithoutInsightsWrite
      let body = encode (object ["actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
      response <- runSession (srequest (adoptRequest (Just tokenText) body)) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue -> hasReasonCode "AUTH_FORBIDDEN" bodyValue
        Nothing -> False

    it "returns 422 when comment contains MNPI-suspected keyword" $ do
      tokenText <- issueTestToken adminWithInsightsWrite
      let body =
            encode
              ( object
                  [ "actionReasonCode" .= ("MANUAL_OPERATION" :: Text)
                  , "comment" .= ("未公表の情報を基に判断" :: Text)
                  ]
              )
      response <- runSession (srequest (adoptRequest (Just tokenText) body)) testApp
      simpleStatus response `shouldBe` status422
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue -> hasReasonCode "COMPLIANCE_MNPI_SUSPECTED" bodyValue
        Nothing -> False

  describe "POST /insights/{identifier}/reject" $ do
    it "returns 401 when Authorization header is missing" $ do
      let body = encode (object ["actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
      response <- runSession (srequest (rejectRequest Nothing body)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 401 when Authorization header has invalid token" $ do
      let body = encode (object ["actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
      response <- runSession (srequest (rejectRequest (Just "invalid.jwt.token") body)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 403 when token lacks insights:write permission" $ do
      tokenText <- issueTestToken viewerWithoutInsightsWrite
      let body = encode (object ["actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
      response <- runSession (srequest (rejectRequest (Just tokenText) body)) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue -> hasReasonCode "AUTH_FORBIDDEN" bodyValue
        Nothing -> False

    it "returns 422 when comment contains MNPI-suspected keyword" $ do
      tokenText <- issueTestToken adminWithInsightsWrite
      let body =
            encode
              ( object
                  [ "actionReasonCode" .= ("RISK_REJECTION" :: Text)
                  , "comment" .= ("内部情報に基づく却下" :: Text)
                  ]
              )
      response <- runSession (srequest (rejectRequest (Just tokenText) body)) testApp
      simpleStatus response `shouldBe` status422
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue -> hasReasonCode "COMPLIANCE_MNPI_SUSPECTED" bodyValue
        Nothing -> False

  describe "POST /insights/{identifier}/hypothesize" $ do
    it "returns 401 when Authorization header is missing" $ do
      let body = LazyByteString.fromStrict "{}"
      response <- runSession (srequest (hypothesizeRequest Nothing body)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 401 when Authorization header has invalid token" $ do
      let body = LazyByteString.fromStrict "{}"
      response <- runSession (srequest (hypothesizeRequest (Just "invalid.jwt.token") body)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 403 when token lacks insights:write permission" $ do
      tokenText <- issueTestToken viewerWithoutInsightsWrite
      let body = LazyByteString.fromStrict "{}"
      response <- runSession (srequest (hypothesizeRequest (Just tokenText) body)) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue -> hasReasonCode "AUTH_FORBIDDEN" bodyValue
        Nothing -> False

    it "returns 422 when comment contains MNPI-suspected keyword" $ do
      tokenText <- issueTestToken adminWithInsightsWrite
      let body =
            encode
              ( object
                  [ "comment" .= ("非公開情報あり" :: Text)
                  ]
              )
      response <- runSession (srequest (hypothesizeRequest (Just tokenText) body)) testApp
      simpleStatus response `shouldBe` status422
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue -> hasReasonCode "COMPLIANCE_MNPI_SUSPECTED" bodyValue
        Nothing -> False
