{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

{- | Servant API type definition for the BFF service.

Defines 'BffAPI' as the business API (excluding the standard health
endpoints which are added by 'App.Bootstrap.mkApplication').

Endpoints:
  * @POST /auth/login@ — returns a signed RS256 JWT on valid credentials
-}
module Presentation.Api (
  BffAPI,
  BffPublicAPI,
  bffApiProxy,
  bffServer,
)
where

import Presentation.AppM (AppEnv)
import Presentation.Handler.Auth (LoginRequest, LoginResponse, loginHandler)
import Servant (JSON, Post, Proxy (..), ReqBody, Server, (:>))

-- ---------------------------------------------------------------------------
-- API type (Must-08)
-- ---------------------------------------------------------------------------

type BffPublicAPI =
  "auth"
    :> "login"
    :> ReqBody '[JSON] LoginRequest
    :> Post '[JSON] LoginResponse

type BffAPI = BffPublicAPI

bffApiProxy :: Proxy BffAPI
bffApiProxy = Proxy

-- ---------------------------------------------------------------------------
-- Server
-- ---------------------------------------------------------------------------

{- | Wire 'BffAPI' to its handler.  Must-01 result line:
@POST /auth/login@ → 'loginHandler'.
-}
bffServer :: AppEnv -> Server BffAPI
bffServer = loginHandler
