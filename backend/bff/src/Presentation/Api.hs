{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

{- | Servant API type definition for the BFF service.

Defines 'BffAPI' as the business API (excluding the standard health
endpoints which are added by 'App.Bootstrap.mkApplication').

Endpoints:
  * @POST /auth/login@            — returns a signed HS256 JWT on valid credentials
  * @GET /dashboard/summary@      — returns aggregated dashboard state (JWT required)
-}
module Presentation.Api (
  BffAPI,
  BffPublicAPI,
  bffApiProxy,
  bffServer,
)
where

import Data.Text (Text)
import Presentation.AppM (AppEnv)
import Presentation.Handler.Auth (LoginRequest, LoginResponse, loginHandler)
import Presentation.Handler.Dashboard (DashboardSummaryResponse, getDashboardSummaryHandler)
import Servant (
  Get,
  Header,
  JSON,
  Post,
  Proxy (..),
  ReqBody,
  Server,
  (:<|>) (..),
  (:>),
 )

-- ---------------------------------------------------------------------------
-- API type
-- ---------------------------------------------------------------------------

type BffPublicAPI =
  "auth"
    :> "login"
    :> ReqBody '[JSON] LoginRequest
    :> Post '[JSON] LoginResponse

type BffProtectedAPI =
  "dashboard"
    :> "summary"
    :> Header "Authorization" Text
    :> Get '[JSON] DashboardSummaryResponse

type BffAPI = BffPublicAPI :<|> BffProtectedAPI

bffApiProxy :: Proxy BffAPI
bffApiProxy = Proxy

-- ---------------------------------------------------------------------------
-- Server
-- ---------------------------------------------------------------------------

{- | Wire 'BffAPI' to its handlers.

  * @POST /auth/login@       → 'loginHandler'
  * @GET /dashboard/summary@ → 'getDashboardSummaryHandler'
-}
bffServer :: AppEnv -> Server BffAPI
bffServer appEnvironment =
  loginHandler appEnvironment
    :<|> getDashboardSummaryHandler appEnvironment
