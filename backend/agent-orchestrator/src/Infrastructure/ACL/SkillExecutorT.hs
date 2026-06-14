{- | ACL adapter for external Skill Runtime HTTP API.

Must-01: Infrastructure.ACL.SkillExecutorT implements SkillExecutor typeclass.
Must-03: newtype SkillExecutorT + runSkillExecutorT.
Must-04: SkillExecutor (SkillExecutorT IO) instance.
Must-05: SkillExecutorEnv with endpointUrl, timeoutSeconds, httpExecute.
Must-06: SKILL_EXECUTOR_ENDPOINT constant documented here.
Must-07: POST request with JSON body { skillName, skillVersion, promptHash, contextPayload }.
Must-08: Response body decoded to SkillOutput; failure → DependencyUnavailable.
Must-09: 5xx → DependencyUnavailable.
Must-10: 4xx → DependencyUnavailable.
Must-11: ResponseTimeout / ConnectionTimeout → DependencyTimeout.
Must-12: ConnectionFailure → DependencyUnavailable.
Must-13: InvalidUrlException → MissingRequiredFields ["endpointUrl"].
Must-14: mapSkillExecutorException internal function.
-}
module Infrastructure.ACL.SkillExecutorT (
  -- * Environment variable name (for Main.hs wiring)
  skillExecutorEndpointEnvVar,

  -- * Environment
  SkillExecutorEnv (..),

  -- * Monad transformer
  SkillExecutorT (..),
  runSkillExecutorT,
) where

import Control.Exception (try)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.Class (MonadTrans)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson (FromJSON, ToJSON)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.SkillExecutor (
  SkillExecutor (..),
  SkillInput (..),
  SkillOutput (..),
 )
import GHC.Generics (Generic)
import Network.HTTP.Client (
  HttpException (..),
  HttpExceptionContent (..),
  Request,
  RequestBody (..),
  Response,
  method,
  parseRequest_,
  requestBody,
  requestHeaders,
  responseBody,
  responseStatus,
 )
import Network.HTTP.Types (statusCode)

-- ---------------------------------------------------------------------------
-- Environment variable name (Must-06)
-- ---------------------------------------------------------------------------

{- | Must-06: Environment variable name for skill executor endpoint.
Read from environment as: @SKILL_EXECUTOR_ENDPOINT@.
Wiring into 'SkillExecutorEnv.endpointUrl' is the responsibility of Main.hs.
-}
skillExecutorEndpointEnvVar :: Text
skillExecutorEndpointEnvVar = "SKILL_EXECUTOR_ENDPOINT"

-- ---------------------------------------------------------------------------
-- Environment (Must-05)
-- ---------------------------------------------------------------------------

{- | Must-05: Skill executor adapter environment.
'endpointUrl' is read from @SKILL_EXECUTOR_ENDPOINT@ at startup.
'timeoutSeconds' defaults to 30.
'httpExecute' enables transport substitution in tests.
-}
data SkillExecutorEnv = SkillExecutorEnv
  { endpointUrl :: Text
  -- ^ Must-05: URL for the external skill runtime. Read from SKILL_EXECUTOR_ENDPOINT.
  , timeoutSeconds :: Int
  -- ^ Must-05: HTTP response timeout in seconds (default 30).
  , httpExecute :: Request -> IO (Response ByteString.Lazy.ByteString)
  -- ^ Must-05: HTTP transport capability — replaced in tests.
  }

-- ---------------------------------------------------------------------------
-- Monad transformer (Must-03)
-- ---------------------------------------------------------------------------

newtype SkillExecutorT m a = SkillExecutorT
  { unSkillExecutorT :: ReaderT SkillExecutorEnv m a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO, MonadTrans)

runSkillExecutorT :: SkillExecutorEnv -> SkillExecutorT m a -> m a
runSkillExecutorT environment action =
  runReaderT (unSkillExecutorT action) environment

-- ---------------------------------------------------------------------------
-- SkillExecutor instance (Must-04)
-- ---------------------------------------------------------------------------

instance (MonadIO m) => SkillExecutor (SkillExecutorT m) where
  executeSkill skillInput = SkillExecutorT $ do
    environment <- ask
    liftIO (executeSkillIO environment skillInput)

-- ---------------------------------------------------------------------------
-- Core execution logic
-- ---------------------------------------------------------------------------

-- | Must-07/Must-08/Must-09/Must-10: Build POST request, call httpExecute, decode response.
executeSkillIO ::
  SkillExecutorEnv ->
  SkillInput ->
  IO (Either DomainError SkillOutput)
executeSkillIO environment skillInput = do
  let requestPayload =
        SkillRequestPayload
          { skillName = skillInput.skillName
          , skillVersion = skillInput.skillVersion
          , promptHash = skillInput.promptHash
          , contextPayload = skillInput.contextPayload
          }
      request =
        (parseRequest_ (Text.unpack environment.endpointUrl))
          { method = "POST"
          , requestBody = RequestBodyLBS (Aeson.encode requestPayload)
          , requestHeaders =
              [ ("Content-Type", "application/json")
              , ("Accept", "application/json")
              , ("X-Trace-Id", Text.Encoding.encodeUtf8 skillInput.promptHash)
              ]
          }
  responseResult <- try @HttpException (environment.httpExecute request)
  case responseResult of
    Left httpException -> pure (Left (mapSkillExecutorException httpException))
    Right response -> do
      let statusCodeValue = statusCode (responseStatus response)
      if statusCodeValue >= 400
        then
          pure
            ( Left
                ( InvariantViolation
                    "SkillExecutor"
                    ("HTTP " <> Text.pack (show statusCodeValue))
                    DependencyUnavailable
                )
            )
        else case Aeson.eitherDecode @SkillResponsePayload (responseBody response) of
          Left parseError ->
            pure
              ( Left
                  ( InvariantViolation
                      "SkillExecutor"
                      ("JSON decode failure: " <> Text.pack parseError)
                      DependencyUnavailable
                  )
              )
          Right skillResponsePayload ->
            pure
              ( Right
                  SkillOutput
                    { generatedContent = skillResponsePayload.generatedContent
                    , llmModel = skillResponsePayload.llmModel
                    , sourceEvidence = skillResponsePayload.sourceEvidence
                    }
              )

-- ---------------------------------------------------------------------------
-- Error mapping (Must-14)
-- ---------------------------------------------------------------------------

{- | Must-14: Map HttpException to DomainError.
Must-11: ResponseTimeout / ConnectionTimeout → DependencyTimeout.
Must-12: ConnectionFailure → DependencyUnavailable.
Must-13: InvalidUrlException → MissingRequiredFields.
-}
mapSkillExecutorException :: HttpException -> DomainError
mapSkillExecutorException (HttpExceptionRequest _ exceptionContent) =
  case exceptionContent of
    ResponseTimeout ->
      InvariantViolation "SkillExecutor" "timeout" DependencyTimeout
    ConnectionTimeout ->
      InvariantViolation "SkillExecutor" "timeout" DependencyTimeout
    ConnectionFailure cause ->
      InvariantViolation
        "SkillExecutor"
        ("connection failure: " <> Text.pack (show cause))
        DependencyUnavailable
    other ->
      InvariantViolation
        "SkillExecutor"
        ("HTTP exception: " <> Text.pack (show other))
        DependencyUnavailable
mapSkillExecutorException (InvalidUrlException _endpointUrlValue _reason) =
  MissingRequiredFields
    ["endpointUrl"]
    DependencyUnavailable

-- ---------------------------------------------------------------------------
-- JSON wire types
-- ---------------------------------------------------------------------------

-- | Must-07: JSON request body schema.
data SkillRequestPayload = SkillRequestPayload
  { skillName :: Text
  , skillVersion :: Text
  , promptHash :: Text
  , contextPayload :: Text
  }
  deriving stock (Generic)

instance ToJSON SkillRequestPayload

-- | Must-08: JSON response body schema.
data SkillResponsePayload = SkillResponsePayload
  { generatedContent :: Text
  , llmModel :: Text
  , sourceEvidence :: [Text]
  }
  deriving stock (Generic)

instance FromJSON SkillResponsePayload
