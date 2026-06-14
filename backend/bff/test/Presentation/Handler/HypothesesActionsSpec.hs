module Presentation.Handler.HypothesesActionsSpec (spec) where

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
    , hypothesisPromotedTopicName = "test-hypothesis-promoted-topic"
    , hypothesisRejectedTopicName = "test-hypothesis-rejected-topic"
    , hypothesisRetestRequestedTopicName = "test-hypothesis-retest-requested-topic"
    }

testApp :: Application
testApp = serve bffApiProxy (bffServer testAppEnv)

-- | Admin user with hypotheses:decide permission.
adminWithHypothesesDecide :: AuthenticatedUser
adminWithHypothesesDecide =
  AuthenticatedUser
    { identifier = "admin-001"
    , email = EmailAddress "admin@example.com"
    , role = Admin
    , permissions =
        [ AuthPermission "hypotheses:decide"
        , AuthPermission "hypotheses:retest"
        ]
    }

-- | Viewer without hypotheses mutation permissions.
viewerWithoutHypothesesWrite :: AuthenticatedUser
viewerWithoutHypothesesWrite =
  AuthenticatedUser
    { identifier = "viewer-001"
    , email = EmailAddress "viewer@example.com"
    , role = Viewer
    , permissions = [AuthPermission "hypotheses:read"]
    }

issueTestToken :: AuthenticatedUser -> IO Text
issueTestToken authenticatedUser = do
  tokenResult <- issueToken testJwtIssuerEnv authenticatedUser
  case tokenResult of
    Left errorText -> error ("Failed to issue test token: " <> show errorText)
    Right tokenText -> pure tokenText

promoteRequest :: Maybe Text -> ByteString -> SRequest
promoteRequest maybeToken body =
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
          "/hypotheses/01ARZ3NDEKTSV4RRFFQ69G5FAV/promote"
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
          "/hypotheses/01ARZ3NDEKTSV4RRFFQ69G5FAV/reject"
    , simpleRequestBody = body
    }

retestRequest :: Maybe Text -> SRequest
retestRequest maybeToken =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { Wai.requestMethod = "POST"
            , Wai.requestHeaders =
                [("Accept", "application/json")]
                  <> case maybeToken of
                    Nothing -> []
                    Just tokenText ->
                      [("Authorization", "Bearer " <> encodeUtf8 tokenText)]
            }
          "/hypotheses/01ARZ3NDEKTSV4RRFFQ69G5FAV/retest"
    , simpleRequestBody = ""
    }

mnpiSelfDeclarationRequest :: Maybe Text -> ByteString -> SRequest
mnpiSelfDeclarationRequest maybeToken body =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { Wai.requestMethod = "PUT"
            , Wai.requestHeaders =
                [("Content-Type", "application/json"), ("Accept", "application/json")]
                  <> case maybeToken of
                    Nothing -> []
                    Just tokenText ->
                      [("Authorization", "Bearer " <> encodeUtf8 tokenText)]
            }
          "/hypotheses/01ARZ3NDEKTSV4RRFFQ69G5FAV/mnpi-self-declaration"
    , simpleRequestBody = body
    }

lookupText :: String -> Value -> Maybe Aeson.Value
lookupText key (Aeson.Object obj) = KeyMap.lookup (Key.fromString key) obj
lookupText _ _ = Nothing

hasReasonCode :: Text -> Value -> Bool
hasReasonCode expectedCode bodyValue =
  case lookupText "reasonCode" bodyValue of
    Just (Aeson.String code) -> code == expectedCode
    _ -> False

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Presentation.Handler.Hypotheses (action endpoints)" $ do
  describe "POST /hypotheses/{identifier}/promote" $ do
    it "returns 401 when Authorization header is missing" $ do
      let body = encode (object ["actionReasonCode" .= ("MODEL_REVIEW_DECISION" :: Text), "mnpiSelfDeclared" .= True])
      response <- runSession (srequest (promoteRequest Nothing body)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 401 when Authorization header has invalid token" $ do
      let body = encode (object ["actionReasonCode" .= ("MODEL_REVIEW_DECISION" :: Text), "mnpiSelfDeclared" .= True])
      response <- runSession (srequest (promoteRequest (Just "invalid.jwt.token") body)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 403 when token lacks hypotheses:decide permission" $ do
      tokenText <- issueTestToken viewerWithoutHypothesesWrite
      let body = encode (object ["actionReasonCode" .= ("MODEL_REVIEW_DECISION" :: Text), "mnpiSelfDeclared" .= True])
      response <- runSession (srequest (promoteRequest (Just tokenText) body)) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue -> hasReasonCode "AUTH_FORBIDDEN" bodyValue
        Nothing -> False

  describe "POST /hypotheses/{identifier}/reject" $ do
    it "returns 401 when Authorization header is missing" $ do
      let body = encode (object ["actionReasonCode" .= ("POLICY_COMPLIANCE_HOLD" :: Text)])
      response <- runSession (srequest (rejectRequest Nothing body)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 401 when Authorization header has invalid token" $ do
      let body = encode (object ["actionReasonCode" .= ("POLICY_COMPLIANCE_HOLD" :: Text)])
      response <- runSession (srequest (rejectRequest (Just "invalid.jwt.token") body)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 403 when token lacks hypotheses:decide permission" $ do
      tokenText <- issueTestToken viewerWithoutHypothesesWrite
      let body = encode (object ["actionReasonCode" .= ("POLICY_COMPLIANCE_HOLD" :: Text)])
      response <- runSession (srequest (rejectRequest (Just tokenText) body)) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue -> hasReasonCode "AUTH_FORBIDDEN" bodyValue
        Nothing -> False

  describe "POST /hypotheses/{identifier}/retest" $ do
    it "returns 401 when Authorization header is missing" $ do
      response <- runSession (srequest (retestRequest Nothing)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 401 when Authorization header has invalid token" $ do
      response <- runSession (srequest (retestRequest (Just "invalid.jwt.token"))) testApp
      simpleStatus response `shouldBe` status401

    it "returns 403 when token lacks hypotheses:retest permission" $ do
      tokenText <- issueTestToken viewerWithoutHypothesesWrite
      response <- runSession (srequest (retestRequest (Just tokenText))) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue -> hasReasonCode "AUTH_FORBIDDEN" bodyValue
        Nothing -> False

  describe "PUT /hypotheses/{identifier}/mnpi-self-declaration" $ do
    it "returns 401 when Authorization header is missing" $ do
      let body = encode (object ["mnpiSelfDeclared" .= True, "actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
      response <- runSession (srequest (mnpiSelfDeclarationRequest Nothing body)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 401 when Authorization header has invalid token" $ do
      let body = encode (object ["mnpiSelfDeclared" .= True, "actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
      response <- runSession (srequest (mnpiSelfDeclarationRequest (Just "invalid.jwt.token") body)) testApp
      simpleStatus response `shouldBe` status401

    it "returns 403 when token lacks hypotheses:decide permission" $ do
      tokenText <- issueTestToken viewerWithoutHypothesesWrite
      let body = encode (object ["mnpiSelfDeclared" .= True, "actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
      response <- runSession (srequest (mnpiSelfDeclarationRequest (Just tokenText) body)) testApp
      simpleStatus response `shouldBe` status403
      let maybeBody = decode (simpleBody response) :: Maybe Value
      maybeBody `shouldSatisfy` \case
        Just bodyValue -> hasReasonCode "AUTH_FORBIDDEN" bodyValue
        Nothing -> False
