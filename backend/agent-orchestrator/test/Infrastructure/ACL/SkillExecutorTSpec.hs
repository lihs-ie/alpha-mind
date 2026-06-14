module Infrastructure.ACL.SkillExecutorTSpec (spec) where

import Control.Exception (SomeException (..), throwIO)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as Aeson.KeyMap
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.IORef (newIORef, readIORef, writeIORef)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.SkillExecutor (
  SkillExecutor (..),
  SkillInput (..),
  SkillOutput (..),
 )
import Infrastructure.ACL.SkillExecutorT (
  SkillExecutorEnv (..),
  runSkillExecutorT,
 )
import Network.HTTP.Client (
  HttpException (..),
  HttpExceptionContent (..),
  Request,
  RequestBody (..),
  Response,
  defaultRequest,
  requestBody,
 )
import Network.HTTP.Client.Internal (CookieJar (..), Response (..), ResponseClose (..))
import Network.HTTP.Types (http11, status200, status500, status503)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- Test fixtures
-- ---------------------------------------------------------------------------

testSkillInput :: SkillInput
testSkillInput =
  SkillInput
    { skillName = "hypothesis-skill"
    , skillVersion = "1.0.0"
    , promptHash = "sha256-abc123"
    , contextPayload = "market data context payload"
    }

buildJsonResponse :: Int -> ByteString.Lazy.ByteString -> Response ByteString.Lazy.ByteString
buildJsonResponse statusCodeValue body =
  Response
    { responseStatus =
        if statusCodeValue >= 500
          then if statusCodeValue == 503 then status503 else status500
          else status200
    , responseVersion = http11
    , responseHeaders = []
    , responseBody = body
    , responseCookieJar = CJ []
    , responseClose' = ResponseClose (pure ())
    , responseOriginalRequest = defaultRequest
    , responseEarlyHints = []
    }

validSkillOutputJson :: ByteString.Lazy.ByteString
validSkillOutputJson =
  Aeson.encode $
    Aeson.object
      [ "generatedContent" Aeson..= ("Hypothesis: 7203.T is undervalued." :: String)
      , "llmModel" Aeson..= ("gpt-4o" :: String)
      , "sourceEvidence" Aeson..= (["evidence-1", "evidence-2"] :: [String])
      ]

makeEnv :: (Request -> IO (Response ByteString.Lazy.ByteString)) -> SkillExecutorEnv
makeEnv fakeHttp =
  SkillExecutorEnv
    { endpointUrl = "http://localhost:8080/execute"
    , timeoutSeconds = 30
    , httpExecute = fakeHttp
    }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

isDependencyUnavailable :: DomainError -> Bool
isDependencyUnavailable (InvariantViolation _ _ DependencyUnavailable) = True
isDependencyUnavailable _ = False

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
  describe "Infrastructure.ACL.SkillExecutorT" $ do
    -- TC-ACL-SKILL-01: Success — 200 with valid JSON → Right SkillOutput
    describe "TC-ACL-SKILL-01: 200 OK with valid JSON" $ do
      it "returns Right SkillOutput with correct fields" $ do
        let fakeHttp _ = pure (buildJsonResponse 200 validSkillOutputJson)
        let environment = makeEnv fakeHttp
        result <- runSkillExecutorT environment (executeSkill testSkillInput)
        case result of
          Left domainError -> fail ("Expected Right, got Left: " <> show domainError)
          Right skillOutput -> do
            skillOutput.generatedContent `shouldBe` "Hypothesis: 7203.T is undervalued."
            skillOutput.llmModel `shouldBe` "gpt-4o"
            skillOutput.sourceEvidence `shouldBe` ["evidence-1", "evidence-2"]

      it "sends POST request with skillName in body (Must-07)" $ do
        capturedBodyRef <- newIORef ByteString.Lazy.empty
        let fakeHttp request = do
              case requestBody request of
                RequestBodyLBS body -> writeIORef capturedBodyRef body
                _ -> pure ()
              pure (buildJsonResponse 200 validSkillOutputJson)
        let environment = makeEnv fakeHttp
        _result <- runSkillExecutorT environment (executeSkill testSkillInput)
        capturedBody <- readIORef capturedBodyRef
        case Aeson.decode capturedBody of
          Nothing -> fail "Expected JSON body in request"
          Just jsonValue ->
            case jsonValue of
              Aeson.Object objectMap ->
                Aeson.KeyMap.lookup "skillName" objectMap `shouldBe` Just (Aeson.String "hypothesis-skill")
              _ -> fail "Expected JSON object"

    -- TC-ACL-SKILL-02: ResponseTimeout → Left DependencyTimeout
    describe "TC-ACL-SKILL-02: ResponseTimeout → DependencyTimeout (Must-11)" $ do
      it "returns Left InvariantViolation with DependencyTimeout on ResponseTimeout" $ do
        let fakeHttp _ = throwIO (HttpExceptionRequest defaultRequest ResponseTimeout)
        let environment = makeEnv fakeHttp
        result <- runSkillExecutorT environment (executeSkill testSkillInput)
        result `shouldBe` Left (InvariantViolation "SkillExecutor" "timeout" DependencyTimeout)

    -- TC-ACL-SKILL-03: ConnectionFailure → Left DependencyUnavailable
    describe "TC-ACL-SKILL-03: ConnectionFailure → DependencyUnavailable (Must-12)" $ do
      it "returns Left with DependencyUnavailable on ConnectionFailure" $ do
        let cause = userError "connection refused"
        let fakeHttp _ = throwIO (HttpExceptionRequest defaultRequest (ConnectionFailure (SomeException cause)))
        let environment = makeEnv fakeHttp
        result <- runSkillExecutorT environment (executeSkill testSkillInput)
        case result of
          Right _ -> fail "Expected Left"
          Left domainError -> domainError `shouldSatisfy` isDependencyUnavailable

    -- TC-ACL-SKILL-04: 5xx → Left DependencyUnavailable
    describe "TC-ACL-SKILL-04: 5xx status → DependencyUnavailable (Must-09)" $ do
      it "returns Left with DependencyUnavailable on 503" $ do
        let fakeHttp _ = pure (buildJsonResponse 503 "Service Unavailable")
        let environment = makeEnv fakeHttp
        result <- runSkillExecutorT environment (executeSkill testSkillInput)
        case result of
          Right _ -> fail "Expected Left"
          Left domainError -> domainError `shouldSatisfy` isDependencyUnavailable

      it "returns Left with DependencyUnavailable on 500" $ do
        let fakeHttp _ = pure (buildJsonResponse 500 "Internal Server Error")
        let environment = makeEnv fakeHttp
        result <- runSkillExecutorT environment (executeSkill testSkillInput)
        case result of
          Right _ -> fail "Expected Left"
          Left domainError -> domainError `shouldSatisfy` isDependencyUnavailable

    -- TC-ACL-SKILL-05: Invalid JSON → Left DependencyUnavailable
    describe "TC-ACL-SKILL-05: Invalid JSON → DependencyUnavailable (Must-08)" $ do
      it "returns Left with DependencyUnavailable when response body is not valid JSON" $ do
        let fakeHttp _ = pure (buildJsonResponse 200 "not valid json at all {{{")
        let environment = makeEnv fakeHttp
        result <- runSkillExecutorT environment (executeSkill testSkillInput)
        case result of
          Right _ -> fail "Expected Left"
          Left domainError -> domainError `shouldSatisfy` isDependencyUnavailable

      it "returns Left with DependencyUnavailable when JSON is missing required fields" $ do
        let incompleteJson = Aeson.encode (Aeson.object ["generatedContent" Aeson..= ("only this" :: String)])
        let fakeHttp _ = pure (buildJsonResponse 200 incompleteJson)
        let environment = makeEnv fakeHttp
        result <- runSkillExecutorT environment (executeSkill testSkillInput)
        case result of
          Right _ -> fail "Expected Left"
          Left domainError -> domainError `shouldSatisfy` isDependencyUnavailable
