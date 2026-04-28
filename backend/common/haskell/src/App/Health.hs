{-# LANGUAGE OverloadedStrings #-}

module App.Health (
  ServiceStatusResponse (..),
  ServiceHealthContext (..),
  StandardHealthAPI,
  healthServer,
)
where

import Data.Aeson (ToJSON (toJSON), object, (.=))
import Data.Text qualified as Text
import Servant (JSON, PlainText, Server, (:<|>) (..), type (:>))
import Servant.API (Get)

data ServiceHealthContext = ServiceHealthContext
  { serviceName :: Text.Text
  , serviceVersion :: Text.Text
  , serviceRevision :: Maybe Text.Text
  }

data ServiceStatusResponse = ServiceStatusResponse
  { service :: Text.Text
  , status :: Text.Text
  , version :: Text.Text
  , revision :: Maybe Text.Text
  }

instance ToJSON ServiceStatusResponse where
  toJSON response =
    object
      [ "service" .= service response
      , "status" .= status response
      , "version" .= version response
      , "revision" .= revision response
      ]

type StandardHealthAPI =
  "healthz"
    :> Get '[PlainText] Text.Text
    :<|> Get '[JSON] ServiceStatusResponse

healthServer :: ServiceHealthContext -> Server StandardHealthAPI
healthServer context =
  pure (Text.pack "ok")
    :<|> pure
      ServiceStatusResponse
        { service = serviceName context
        , status = Text.pack "running"
        , version = serviceVersion context
        , revision = serviceRevision context
        }
