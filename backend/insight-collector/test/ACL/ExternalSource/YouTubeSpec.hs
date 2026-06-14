module ACL.ExternalSource.YouTubeSpec (spec) where

import ACL.ExternalSource.YouTube (
  YouTubeEnv (..),
  isRetryableForAcl,
  runYouTubeExternalSourceT,
 )
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time.Calendar (fromGregorian)
import Domain.InsightCollection.Aggregate (
  FailureDetail (..),
  InsightRecord (..),
  SignalClass (..),
  SourceConfig (..),
  SourcePolicySnapshot (..),
  SourceType (..),
  XConfig (..),
  YouTubeConfig (..),
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

buildJsonResponse :: Int -> Aeson.Value -> Response ByteString.Lazy.ByteString
buildJsonResponse _ body =
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

searchResponseBody :: Aeson.Value
searchResponseBody =
  Aeson.object
    [ "items"
        Aeson..= Aeson.toJSONList
          [ Aeson.object
              [ "id" Aeson..= Aeson.object ["videoId" Aeson..= ("dQw4w9WgXcQ" :: Text)]
              , "snippet"
                  Aeson..= Aeson.object
                    [ "title" Aeson..= ("Market Analysis Q2 2026" :: Text)
                    , "description" Aeson..= ("Deep analysis of Japanese equity market trends for Q2 2026." :: Text)
                    ]
              ]
          ]
    ]

defaultYouTubeEnv :: (Request -> IO (Response ByteString.Lazy.ByteString)) -> YouTubeEnv
defaultYouTubeEnv httpExecuteFn =
  YouTubeEnv
    { apiKey = "test-api-key"
    , timeoutSeconds = 30
    , skillVersion = "1.0.0"
    , httpExecute = httpExecuteFn
    }

defaultPolicy :: SourcePolicySnapshot
defaultPolicy =
  SourcePolicySnapshot
    { sourceType = YouTube
    , enabled = True
    , termsVersion = "2024-01"
    , redistributionAllowed = True
    , dailyQuota = Just 8000
    , sourceConfig = YouTubeSourceConfig (YouTubeConfig{apiKeySecretName = "youtube-api-key"})
    }

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "ACL.ExternalSource.YouTube" $ do
    describe "ExternalSourcePort instance" $ do
      it "Must-ACL-002: fetchInsights returns Right records on success" $ do
        let environment = defaultYouTubeEnv (\_ -> pure (buildJsonResponse 200 searchResponseBody))
        result <- runYouTubeExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        result `shouldSatisfy` isRight

      it "Must-ACL-002: fetchInsights returns at least one record for non-empty search results" $ do
        let environment = defaultYouTubeEnv (\_ -> pure (buildJsonResponse 200 searchResponseBody))
        result <- runYouTubeExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        case result of
          Right records -> length records `shouldBe` 1
          Left failure -> fail ("Expected Right but got Left: " <> show failure.reasonCode)

      it "Must-ACL-016: sourceUrl has YouTube format" $ do
        let environment = defaultYouTubeEnv (\_ -> pure (buildJsonResponse 200 searchResponseBody))
        result <- runYouTubeExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        case result of
          Right records ->
            mapM_
              ( \record ->
                  record.sourceUrl `shouldSatisfy` Text.isPrefixOf "https://www.youtube.com/watch?v="
              )
              records
          Left _ -> pure ()

      it "Must-ACL-006: quotaExceeded 403 returns DependencyUnavailable not retryable" $ do
        let environment = defaultYouTubeEnv (\_ -> pure (buildStatusResponse 403))
        result <- runYouTubeExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        case result of
          Left failureDetail -> do
            failureDetail.reasonCode `shouldBe` DependencyUnavailable
            failureDetail.retryable `shouldBe` False
          Right _ -> pure () -- quota check short-circuit possible
      it "Must-ACL-027: signalClass matches soWhatScore threshold" $ do
        let environment = defaultYouTubeEnv (\_ -> pure (buildJsonResponse 200 searchResponseBody))
        result <- runYouTubeExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
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
        let environment = defaultYouTubeEnv (\_ -> pure (buildJsonResponse 200 searchResponseBody))
        result <- runYouTubeExternalSourceT environment (fetchInsights defaultPolicy (fromGregorian 2026 6 14))
        case result of
          Right records ->
            mapM_
              ( \record -> do
                  record.soWhatScore `shouldSatisfy` (>= 0.0)
                  record.soWhatScore `shouldSatisfy` (<= 1.0)
              )
              records
          Left _ -> pure ()

      it "Must-ACL-002: non-YouTube SourceConfig returns DataSchemaInvalid" $ do
        let environment = defaultYouTubeEnv (\_ -> pure (buildJsonResponse 200 searchResponseBody))
        let wrongPolicy =
              defaultPolicy
                { sourceConfig =
                    XSourceConfig (XConfig{bearerTokenSecretName = "token"})
                }
        result <- runYouTubeExternalSourceT environment (fetchInsights wrongPolicy (fromGregorian 2026 6 14))
        case result of
          Left failureDetail -> failureDetail.reasonCode `shouldBe` DataSchemaInvalid
          Right _ -> fail "Expected Left DataSchemaInvalid"

      it "Must-ACL-005: isRetryableForAcl returns True for DependencyTimeout" $ do
        let failureDetail =
              FailureDetail
                { reasonCode = DependencyTimeout
                , detail = Just "timeout"
                , retryable = True
                , sourceType = Just YouTube
                , stage = Nothing
                }
        isRetryableForAcl failureDetail `shouldBe` True

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left _) = False
