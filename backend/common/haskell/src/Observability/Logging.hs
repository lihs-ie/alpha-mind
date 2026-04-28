{-# OPTIONS_GHC -fno-hpc #-}

module Observability.Logging (
  LogContext (..),
  initLogger,
  logErrorWith,
  logExceptionWith,
  logInfoWith,
) where

import Config.Env (CommonRuntimeEnv (serviceName))
import Control.Exception (SomeException)
import Data.Aeson (ToJSON (toJSON), object, (.=))
import Data.Text qualified as Text
import Katip (
  ColorStrategy (ColorIfTerminal),
  Environment (Environment),
  LogEnv,
  LogItem (..),
  Namespace (Namespace),
  PayloadSelection (AllKeys, SomeKeys),
  Severity (ErrorS, InfoS),
  ToObject (..),
  Verbosity (V0, V2),
  defaultScribeSettings,
  initLogEnv,
  jsonFormat,
  logF,
  ls,
  mkHandleScribeWithFormatter,
  permitItem,
  registerScribe,
  runKatipT,
 )
import System.IO (stdout)

data LogContext = LogContext
  { service :: Text.Text
  , trace :: Maybe Text.Text
  , identifier :: Maybe Text.Text
  , eventType :: Maybe Text.Text
  , reasonCode :: Maybe Text.Text
  }

instance ToJSON LogContext where
  toJSON context =
    object $
      ["service" .= context.service]
        <> maybe [] (\v -> ["trace" .= v]) (trace context)
        <> maybe [] (\v -> ["identifier" .= v]) (identifier context)
        <> maybe [] (\v -> ["eventType" .= v]) (eventType context)
        <> maybe [] (\v -> ["reasonCode" .= v]) (reasonCode context)

instance ToObject LogContext

instance LogItem LogContext where
  payloadKeys V0 _ = SomeKeys ["service"]
  payloadKeys _ _ = AllKeys

initLogger :: CommonRuntimeEnv -> IO LogEnv
initLogger runtime = do
  logEnv <- initLogEnv (Namespace [runtime.serviceName]) (Environment "production")
  scribe <- mkHandleScribeWithFormatter jsonFormat ColorIfTerminal stdout (permitItem InfoS) V2
  registerScribe "stdout" scribe defaultScribeSettings logEnv

logInfoWith :: LogEnv -> LogContext -> Text.Text -> IO ()
logInfoWith env context message =
  runKatipT env $ logF context mempty InfoS (ls message)

logErrorWith :: LogEnv -> LogContext -> Text.Text -> IO ()
logErrorWith env context message =
  runKatipT env $ logF context mempty ErrorS (ls message)

logExceptionWith :: LogEnv -> LogContext -> SomeException -> IO ()
logExceptionWith env context exception =
  runKatipT env $ logF context mempty ErrorS (ls (Text.pack (show exception)))
