{-# OPTIONS_GHC -fno-hpc #-}

module Observability.Logging (
  LogContext (..),
  LogEnv,
  initLogger,
  logErrorWith,
  logExceptionWith,
  logInfoWith,
) where

import Config.Env (CommonRuntimeEnv (serviceName))
import Control.Exception (SomeException)
import Data.Aeson (ToJSON (toJSON), Value, object, (.=))
import Data.HashMap.Strict (HashMap)
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

{- | Structured log context for katip.

 All fields except 'service' are optional so that callers can set only the
 fields relevant to their operation.

 @result@ — the normalised outcome of the audited event (@"success"@ or
 @"failed"@).  Used by 'AuditArchiveRepository.persistArchive'.

 @payloadSummary@ — a map of additional key/value pairs derived from the
 original CloudEvent payload.  Kept as 'HashMap Text Value' so that
 structured JSON logging preserves the nested map without re-encoding.
-}
data LogContext = LogContext
  { service :: Text.Text
  , trace :: Maybe Text.Text
  , identifier :: Maybe Text.Text
  , eventType :: Maybe Text.Text
  , reasonCode :: Maybe Text.Text
  , result :: Maybe Text.Text
  , payloadSummary :: Maybe (HashMap Text.Text Value)
  }

instance ToJSON LogContext where
  toJSON context =
    object $
      ["service" .= context.service]
        <> maybe [] (\v -> ["trace" .= v]) (trace context)
        <> maybe [] (\v -> ["identifier" .= v]) (identifier context)
        <> maybe [] (\v -> ["eventType" .= v]) (eventType context)
        <> maybe [] (\v -> ["reasonCode" .= v]) (reasonCode context)
        <> maybe [] (\v -> ["result" .= v]) (result context)
        <> maybe [] (\v -> ["payloadSummary" .= v]) (payloadSummary context)

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
logInfoWith logEnvironment context message =
  runKatipT logEnvironment $ logF context mempty InfoS (ls message)

logErrorWith :: LogEnv -> LogContext -> Text.Text -> IO ()
logErrorWith logEnvironment context message =
  runKatipT logEnvironment $ logF context mempty ErrorS (ls message)

logExceptionWith :: LogEnv -> LogContext -> SomeException -> IO ()
logExceptionWith logEnvironment context exception =
  runKatipT logEnvironment $ logF context mempty ErrorS (ls (Text.pack (show exception)))
