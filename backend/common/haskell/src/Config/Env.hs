module Config.Env (
  ConfigError (..),
  CommonRuntimeEnv (..),
  loadCommonRuntimeEnv,
  optionalTextEnv,
  requireTextEnv,
)
where

import Control.Applicative ((<|>))
import Control.Exception (Exception, throwIO)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Read qualified as TextRead
import System.Environment (lookupEnv)

data ConfigError
  = MissingEnv Text
  | InvalidEnv Text Text
  deriving stock (Show, Eq)

instance Exception ConfigError

data CommonRuntimeEnv = CommonRuntimeEnv
  { port :: Int
  , gcpProjectId :: Text
  , serviceName :: Text
  , serviceVersion :: Text
  , revision :: Maybe Text
  , logLevel :: Text
  }
  deriving stock (Show, Eq)

requireTextEnv :: Text -> IO Text
requireTextEnv name =
  optionalTextEnv name >>= maybe (throwIO (MissingEnv name)) pure

optionalTextEnv :: Text -> IO (Maybe Text)
optionalTextEnv =
  fmap (fmap Text.pack) . lookupEnv . Text.unpack

parseInt :: Text -> Either Text Int
parseInt input =
  case TextRead.decimal input of
    Right (value, rest)
      | Text.null rest -> Right value
      | otherwise -> Left "unexpected trailing characters"
    Left err -> Left (Text.pack err)

optionalIntEnv :: Text -> IO (Maybe Int)
optionalIntEnv name =
  optionalTextEnv name
    >>= maybe
      (pure Nothing)
      (either (throwIO . InvalidEnv name) (pure . Just) . parseInt)

loadProjectId :: IO Text
loadProjectId =
  (<|>) <$> optionalTextEnv "GCP_PROJECT_ID" <*> optionalTextEnv "GOOGLE_CLOUD_PROJECT"
    >>= maybe (throwIO (MissingEnv "GCP_PROJECT_ID")) pure

validateLogLevel :: Text -> IO Text
validateLogLevel value =
  if value `elem` allowed
    then pure value
    else throwIO (InvalidEnv "LOG_LEVEL" value)
 where
  allowed = ["debug", "info", "warning", "error"]

loadCommonRuntimeEnv :: Text -> IO CommonRuntimeEnv
loadCommonRuntimeEnv name =
  CommonRuntimeEnv . fromMaybe 8080
    <$> optionalIntEnv "PORT"
    <*> loadProjectId
    <*> pure name
    <*> requireTextEnv "SERVICE_VERSION"
    <*> optionalTextEnv "K_REVISION"
    <*> (optionalTextEnv "LOG_LEVEL" >>= validateLogLevel . fromMaybe "info")
