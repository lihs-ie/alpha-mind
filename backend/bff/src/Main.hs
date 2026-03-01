{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeOperators #-}

module Main where

import Data.Aeson (ToJSON)
import Data.Maybe (fromMaybe)
import GHC.Generics (Generic)
import Network.Wai.Handler.Warp (run)
import Servant
import System.Environment (lookupEnv)

-- | サービスステータスのレスポンス型
data ServiceStatus = ServiceStatus
  { service :: String
  , status :: String
  }
  deriving (Generic)

instance ToJSON ServiceStatus

-- | API型定義
type HealthCheckAPI = "healthz" :> Get '[PlainText] String

type StatusAPI = Get '[JSON] ServiceStatus

type API = HealthCheckAPI :<|> StatusAPI

apiProxy :: Proxy API
apiProxy = Proxy

-- | ハンドラー
healthCheckHandler :: Handler String
healthCheckHandler = return "ok"

statusHandler :: Handler ServiceStatus
statusHandler = return ServiceStatus{service = "bff", status = "running"}

server :: Server API
server = healthCheckHandler :<|> statusHandler

main :: IO ()
main = do
  portString <- lookupEnv "PORT"
  let port = read (fromMaybe "8080" portString) :: Int
  putStrLn $ "BFF starting on port " ++ show port
  run port (serve apiProxy server)
