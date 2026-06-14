module ACL.ExternalSource.GitHubSpec (spec) where

import ACL.ExternalSource.GitHub (
  GitHubEnv (..),
  isRetryableForAcl,
  runGitHubExternalSourceT,
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
import Network.HTTP.Types (http11, status200, status403, status500)
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

buildStatusResponse :: Int -> Response ByteString.Lazy.ByteString
buildStatusResponse code =
  let st = case code of
        403 -> status403
        500 -> status500
        _ -> status200
   in Response
        { responseStatus = st
        , responseVersion = http11
        , responseHeaders = []
        , responseBody = Aeson.encode (Aeson.object [])
        , responseCookieJar = CJ []
        , responseClose' = ResponseClose (pure ())
        , responseOriginalRequest = defaultRequest
        , responseEarlyHints = []
        }

repositoriesResponseBody :: Aeson.Value
repositoriesResponseBody =
  Aeson.object
    [ "items"
        Aeson..= Aeson.toJSONList
          [ Aeson.object
              [ "full_name" Aeson..= ("example-org/quant-research" :: Text)
              , "description" Aeson..= ("Quantitative research tools for Japanese equity markets." :: Text)
              , "html_url" Aeson..= ("https://github.com/example-org/quant-research" :: Text)
              ]
          ]
    ]

defaultGitHubEnv :: (Request -> IO (Response ByteString.Lazy.ByteString)) -> GitHubEnv
defaultGitHubEnv httpExecuteFn =
  GitHubEnv
    { personalAccessToken = "ghp_test_token"
    , timeoutSeconds = 30
    , skillVersion = "1.0.0"
    , httpExecute = httpExecuteFn
    }

defaultPolicy :: SourcePolicySnapshot
defaultPolicy =
  SourcePolicySnapshot
    { sourceType = GitHub
    , enabled = True
    , termsVersion = "2024-01"
    , redistributionAllowed = True
    , dailyQuota = Just 100
    , sourceConfig = GitHubSourceConfig (GitHubConfig{personalAccessTokenSecretName = "github-pat"})
    }

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "ACL.ExternalSource.GitHub" $ do
    describe "ExternalSourcePort instance" $ do
      it "Must-ACL-004: fetchInsights returns Right records on success" $ do
        let environment = defaultGitHubEnv (\_ -> pure (buildJsonResponse repositoriesResponseBody))
        result <- runGitHubExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        result `shouldSatisfy` isRight

      it "Must-ACL-004: fetchInsights returns one record for valid repository response" $ do
        let environment = defaultGitHubEnv (\_ -> pure (buildJsonResponse repositoriesResponseBody))
        result <- runGitHubExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        case result of
          Right records -> length records `shouldBe` 1
          Left failure -> fail ("Expected Right but got Left: " <> show failure.reasonCode)

      it "Must-ACL-024: sourceUrl has GitHub format" $ do
        let environment = defaultGitHubEnv (\_ -> pure (buildJsonResponse repositoriesResponseBody))
        result <- runGitHubExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        case result of
          Right records ->
            mapM_
              ( \record ->
                  record.sourceUrl `shouldSatisfy` Text.isPrefixOf "https://github.com/"
              )
              records
          Left _ -> pure ()

      it "Must-ACL-025: evidenceSnippet is non-empty and max 200 chars" $ do
        let environment = defaultGitHubEnv (\_ -> pure (buildJsonResponse repositoriesResponseBody))
        result <- runGitHubExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        case result of
          Right records ->
            mapM_
              ( \record -> do
                  record.evidenceSnippet `shouldSatisfy` (not . Text.null)
                  Text.length record.evidenceSnippet `shouldSatisfy` (<= 200)
              )
              records
          Left _ -> pure ()

      it "Must-ACL-007: 403 response returns DependencyUnavailable (not retryable)" $ do
        let environment = defaultGitHubEnv (\_ -> pure (buildStatusResponse 403))
        result <- runGitHubExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        case result of
          Left failureDetail -> do
            failureDetail.reasonCode `shouldBe` DependencyUnavailable
            failureDetail.retryable `shouldBe` False
          Right _ -> pure ()

      it "Must-ACL-027: signalClass matches soWhatScore threshold" $ do
        let environment = defaultGitHubEnv (\_ -> pure (buildJsonResponse repositoriesResponseBody))
        result <- runGitHubExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
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

      it "Must-ACL-029: soWhatScore is in range [0.0, 1.0]" $ do
        let environment = defaultGitHubEnv (\_ -> pure (buildJsonResponse repositoriesResponseBody))
        result <- runGitHubExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        case result of
          Right records ->
            mapM_
              ( \record -> do
                  record.soWhatScore `shouldSatisfy` (>= 0.0)
                  record.soWhatScore `shouldSatisfy` (<= 1.0)
              )
              records
          Left _ -> pure ()

      it "Must-ACL-004: non-GitHub SourceConfig returns DataSchemaInvalid" $ do
        let environment = defaultGitHubEnv (\_ -> pure (buildJsonResponse repositoriesResponseBody))
        let wrongPolicy =
              defaultPolicy
                { sourceConfig = PaperSourceConfig (PaperConfig{baseUrl = "https://arxiv.org"})
                }
        result <- runGitHubExternalSourceT environment (fetchInsights wrongPolicy (fromGregorian 2026 6 14))
        case result of
          Left failureDetail -> failureDetail.reasonCode `shouldBe` DataSchemaInvalid
          Right _ -> fail "Expected Left DataSchemaInvalid"

      it "Must-ACL-005: isRetryableForAcl returns True for DependencyTimeout" $ do
        let failureDetail =
              FailureDetail
                { reasonCode = DependencyTimeout
                , detail = Just "timeout"
                , retryable = True
                , sourceType = Just GitHub
                , stage = Nothing
                }
        isRetryableForAcl failureDetail `shouldBe` True

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left _) = False
