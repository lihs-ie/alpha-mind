module Presentation.Handler.OrdersActionsSpec (spec) where

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
import Domain.Order.Action (
  OrderTransitionError (..),
  validateApprove,
  validateReject,
  validateRetry,
 )
import Domain.Order.Order (OrderStatus (..))
import Infrastructure.JWT.JwtIssuer (JwtIssuerEnv (..), issueToken)
import Infrastructure.Repository.FirestoreUserRepository (FirestoreUserRepositoryEnv (..))
import Messaging.PubSub (PubSubPublisher (..))
import Network.HTTP.Types (status200, status202, status401, status403, status409)
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

-- | Admin user with orders approve/reject/retry permissions.
adminWithOrdersWrite :: AuthenticatedUser
adminWithOrdersWrite =
  AuthenticatedUser
    { identifier = "admin-001"
    , email = EmailAddress "admin@example.com"
    , role = Admin
    , permissions =
        [ AuthPermission "orders:approve"
        , AuthPermission "orders:reject"
        , AuthPermission "orders:retry"
        ]
    }

-- | Viewer without orders mutation permissions.
viewerWithoutOrdersMutate :: AuthenticatedUser
viewerWithoutOrdersMutate =
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

approveRequest :: Maybe Text -> ByteString -> SRequest
approveRequest maybeToken body =
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
          "/orders/01ARZ3NDEKTSV4RRFFQ69G5FAV/approve"
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
          "/orders/01ARZ3NDEKTSV4RRFFQ69G5FAV/reject"
    , simpleRequestBody = body
    }

retryRequest :: Maybe Text -> SRequest
retryRequest maybeToken =
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
          "/orders/01ARZ3NDEKTSV4RRFFQ69G5FAV/retry"
    , simpleRequestBody = ""
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
-- Domain unit tests: state transition validators
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "Domain.Order.Action" $ do
    describe "validateApprove" $ do
      it "allows PROPOSED → APPROVED when kill switch is disabled" $
        validateApprove False Proposed `shouldBe` Right ()

      it "blocks approve when kill switch is enabled" $
        validateApprove True Proposed `shouldSatisfy` \case
          Left KillSwitchActive -> True
          _ -> False

      it "rejects approve from APPROVED (terminal)" $
        validateApprove False Approved `shouldSatisfy` \case
          Left (InvalidStateTransition Approved _) -> True
          _ -> False

      it "rejects approve from REJECTED (terminal)" $
        validateApprove False Rejected `shouldSatisfy` \case
          Left (InvalidStateTransition Rejected _) -> True
          _ -> False

      it "rejects approve from EXECUTED (terminal)" $
        validateApprove False Executed `shouldSatisfy` \case
          Left (InvalidStateTransition Executed _) -> True
          _ -> False

      it "rejects approve from FAILED" $
        validateApprove False Failed `shouldSatisfy` \case
          Left (InvalidStateTransition Failed _) -> True
          _ -> False

    describe "validateReject" $ do
      it "allows PROPOSED → REJECTED" $
        validateReject Proposed `shouldBe` Right ()

      it "rejects reject from APPROVED" $
        validateReject Approved `shouldSatisfy` \case
          Left (InvalidStateTransition Approved _) -> True
          _ -> False

      it "rejects reject from EXECUTED (terminal)" $
        validateReject Executed `shouldSatisfy` \case
          Left (InvalidStateTransition Executed _) -> True
          _ -> False

    describe "validateRetry" $ do
      it "allows FAILED → PROPOSED when kill switch is disabled" $
        validateRetry False Failed `shouldBe` Right ()

      it "blocks retry when kill switch is enabled" $
        validateRetry True Failed `shouldSatisfy` \case
          Left KillSwitchActive -> True
          _ -> False

      it "rejects retry from PROPOSED" $
        validateRetry False Proposed `shouldSatisfy` \case
          Left (InvalidStateTransition Proposed _) -> True
          _ -> False

      it "rejects retry from APPROVED" $
        validateRetry False Approved `shouldSatisfy` \case
          Left (InvalidStateTransition Approved _) -> True
          _ -> False

  describe "Presentation.Handler.Orders (action endpoints)" $ do
    describe "POST /orders/{identifier}/approve" $ do
      it "returns 401 when Authorization header is missing" $ do
        let body = encode (object ["actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
        response <- runSession (srequest (approveRequest Nothing body)) testApp
        simpleStatus response `shouldBe` status401

      it "returns 401 when Authorization header has invalid token" $ do
        let body = encode (object ["actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
        response <- runSession (srequest (approveRequest (Just "invalid.jwt.token") body)) testApp
        simpleStatus response `shouldBe` status401

      it "returns 403 when token lacks orders:approve permission" $ do
        tokenText <- issueTestToken viewerWithoutOrdersMutate
        let body = encode (object ["actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
        response <- runSession (srequest (approveRequest (Just tokenText) body)) testApp
        simpleStatus response `shouldBe` status403
        let maybeBody = decode (simpleBody response) :: Maybe Value
        maybeBody `shouldSatisfy` \case
          Just bodyValue -> hasReasonCode "AUTH_FORBIDDEN" bodyValue
          Nothing -> False

    describe "POST /orders/{identifier}/reject" $ do
      it "returns 401 when Authorization header is missing" $ do
        let body = encode (object ["actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
        response <- runSession (srequest (rejectRequest Nothing body)) testApp
        simpleStatus response `shouldBe` status401

      it "returns 401 when Authorization header has invalid token" $ do
        let body = encode (object ["actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
        response <- runSession (srequest (rejectRequest (Just "invalid.jwt.token") body)) testApp
        simpleStatus response `shouldBe` status401

      it "returns 403 when token lacks orders:reject permission" $ do
        tokenText <- issueTestToken viewerWithoutOrdersMutate
        let body = encode (object ["actionReasonCode" .= ("MANUAL_OPERATION" :: Text)])
        response <- runSession (srequest (rejectRequest (Just tokenText) body)) testApp
        simpleStatus response `shouldBe` status403
        let maybeBody = decode (simpleBody response) :: Maybe Value
        maybeBody `shouldSatisfy` \case
          Just bodyValue -> hasReasonCode "AUTH_FORBIDDEN" bodyValue
          Nothing -> False

    describe "POST /orders/{identifier}/retry" $ do
      it "returns 401 when Authorization header is missing" $ do
        response <- runSession (srequest (retryRequest Nothing)) testApp
        simpleStatus response `shouldBe` status401

      it "returns 401 when Authorization header has invalid token" $ do
        response <- runSession (srequest (retryRequest (Just "invalid.jwt.token"))) testApp
        simpleStatus response `shouldBe` status401

      it "returns 403 when token lacks orders:retry permission" $ do
        tokenText <- issueTestToken viewerWithoutOrdersMutate
        response <- runSession (srequest (retryRequest (Just tokenText))) testApp
        simpleStatus response `shouldBe` status403
        let maybeBody = decode (simpleBody response) :: Maybe Value
        maybeBody `shouldSatisfy` \case
          Just bodyValue -> hasReasonCode "AUTH_FORBIDDEN" bodyValue
          Nothing -> False
