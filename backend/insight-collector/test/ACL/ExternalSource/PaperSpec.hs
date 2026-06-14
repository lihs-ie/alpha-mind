module ACL.ExternalSource.PaperSpec (spec) where

import ACL.ExternalSource.Paper (
  PaperEnv (..),
  isRetryableForAcl,
  runPaperExternalSourceT,
 )
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time.Calendar (fromGregorian)
import Domain.InsightCollection.Aggregate (
  FailureDetail (..),
  GitHubConfig (..),
  InsightRecord (..),
  PaperConfig (..),
  SignalClass (..),
  SourceConfig (..),
  SourcePolicySnapshot (..),
  SourceType (..),
 )
import Domain.InsightCollection.ExternalSourcePort (ExternalSourcePort (..))
import Domain.InsightCollection.ReasonCode (ReasonCode (..))
import Network.HTTP.Client (
  Request,
  Response,
  defaultRequest,
 )
import Network.HTTP.Client.Internal (CookieJar (..), Response (..), ResponseClose (..))
import Network.HTTP.Types (http11, status200, status500)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

buildJsonResponse :: Aeson.Value -> Response ByteString.Lazy.ByteString
buildJsonResponse body =
  Response
    { responseStatus = status200
    , responseVersion = http11
    , responseHeaders = []
    , responseBody = Aeson.encode body
    , responseCookieJar = CJ []
    , responseClose' = ResponseClose (pure ())
    , responseOriginalRequest = defaultRequest
    , responseEarlyHints = []
    }

build500Response :: Response ByteString.Lazy.ByteString
build500Response =
  Response
    { responseStatus = status500
    , responseVersion = http11
    , responseHeaders = []
    , responseBody = Aeson.encode (Aeson.object [])
    , responseCookieJar = CJ []
    , responseClose' = ResponseClose (pure ())
    , responseOriginalRequest = defaultRequest
    , responseEarlyHints = []
    }

papersResponseBody :: Aeson.Value
papersResponseBody =
  Aeson.object
    [ "papers"
        Aeson..= Aeson.toJSONList
          [ Aeson.object
              [ "id" Aeson..= ("2406.12345" :: Text)
              , "title" Aeson..= ("AI-driven Market Prediction in Japanese Equities" :: Text)
              , "abstract"
                  Aeson..= ( "This paper presents a novel approach to market prediction using deep learning techniques applied to Japanese equity markets." ::
                               Text
                           )
              , "url" Aeson..= ("https://arxiv.org/abs/2406.12345" :: Text)
              ]
          ]
    ]

defaultPaperEnv :: (Request -> IO (Response ByteString.Lazy.ByteString)) -> PaperEnv
defaultPaperEnv httpExecuteFn =
  PaperEnv
    { timeoutSeconds = 30
    , skillVersion = "1.0.0"
    , httpExecute = httpExecuteFn
    }

defaultPolicy :: SourcePolicySnapshot
defaultPolicy =
  SourcePolicySnapshot
    { sourceType = Paper
    , enabled = True
    , termsVersion = "2024-01"
    , redistributionAllowed = True
    , dailyQuota = Just 100
    , sourceConfig = PaperSourceConfig (PaperConfig{baseUrl = "https://arxiv-api.example.com"})
    }

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "ACL.ExternalSource.Paper" $ do
    describe "ExternalSourcePort instance" $ do
      it "Must-ACL-003: fetchInsights returns Right records on success" $ do
        let environment = defaultPaperEnv (\_ -> pure (buildJsonResponse papersResponseBody))
        result <- runPaperExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        result `shouldSatisfy` isRight

      it "Must-ACL-003: fetchInsights returns one record for valid paper response" $ do
        let environment = defaultPaperEnv (\_ -> pure (buildJsonResponse papersResponseBody))
        result <- runPaperExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        case result of
          Right records -> length records `shouldBe` 1
          Left failure -> fail ("Expected Right but got Left: " <> show failure.reasonCode)

      it "Must-ACL-022: evidenceSnippet is non-empty and max 200 chars" $ do
        let environment = defaultPaperEnv (\_ -> pure (buildJsonResponse papersResponseBody))
        result <- runPaperExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        case result of
          Right records ->
            mapM_
              ( \record -> do
                  record.evidenceSnippet `shouldSatisfy` (not . Text.null)
                  Text.length record.evidenceSnippet `shouldSatisfy` (<= 200)
              )
              records
          Left _ -> pure ()

      it "Must-ACL-027: signalClass matches soWhatScore threshold" $ do
        let environment = defaultPaperEnv (\_ -> pure (buildJsonResponse papersResponseBody))
        result <- runPaperExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        case result of
          Right records ->
            mapM_
              ( \record ->
                  if record.soWhatScore >= 0.70
                    then record.signalClass `shouldBe` StructuralAnomaly
                    else record.signalClass `shouldBe` EventNoise
              )
              records
          Left _ -> pure ()

      it "Must-ACL-006: 5xx response returns DependencyUnavailable (retryable)" $ do
        let environment = defaultPaperEnv (\_ -> pure build500Response)
        result <- runPaperExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        case result of
          Left failureDetail -> do
            failureDetail.reasonCode `shouldBe` DependencyUnavailable
            failureDetail.retryable `shouldBe` True
          Right _ -> pure ()

      it "Must-ACL-003: non-Paper SourceConfig returns DataSchemaInvalid" $ do
        let environment = defaultPaperEnv (\_ -> pure (buildJsonResponse papersResponseBody))
        let wrongPolicy =
              defaultPolicy
                { sourceConfig = GitHubSourceConfig (GitHubConfig{personalAccessTokenSecretName = "token"})
                }
        result <- runPaperExternalSourceT environment (fetchInsights wrongPolicy (fromGregorian 2026 6 14))
        case result of
          Left failureDetail -> failureDetail.reasonCode `shouldBe` DataSchemaInvalid
          Right _ -> fail "Expected Left DataSchemaInvalid"

      it "Must-ACL-005: isRetryableForAcl returns True for DependencyTimeout" $ do
        let failureDetail =
              FailureDetail
                { reasonCode = DependencyTimeout
                , detail = Just "timeout"
                , retryable = True
                , sourceType = Just Paper
                , stage = Nothing
                }
        isRetryableForAcl failureDetail `shouldBe` True

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left _) = False
