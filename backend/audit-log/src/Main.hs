{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeOperators #-}

module Main where

import Data.Maybe (fromMaybe)
import GHC.Generics (Generic)
import Data.Aeson (ToJSON)
import Network.Wai.Handler.Warp (run)
import Servant
import System.Environment (lookupEnv)

data ServiceStatus = ServiceStatus
  { service :: String
  , status :: String
  } deriving (Generic)

instance ToJSON ServiceStatus

type HealthCheckAPI = "healthz" :> Get '[PlainText] String
type StatusAPI = Get '[JSON] ServiceStatus
type API = HealthCheckAPI :<|> StatusAPI

apiProxy :: Proxy API
apiProxy = Proxy

healthCheckHandler :: Handler String
healthCheckHandler = return "ok"

statusHandler :: Handler ServiceStatus
statusHandler = return ServiceStatus {service = "audit-log", status = "running"}

server :: Server API
server = healthCheckHandler :<|> statusHandler

main :: IO ()
main = do
  portString <- lookupEnv "PORT"
  let port = read (fromMaybe "8080" portString) :: Int
  putStrLn $ "audit-log starting on port " ++ show port
  run port (serve apiProxy server)
