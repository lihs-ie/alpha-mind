{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

{- | Servant API type definition for the BFF service.

Defines 'BffAPI' as the business API (excluding the standard health
endpoints which are added by 'App.Bootstrap.mkApplication').

Endpoints:
  * @POST /auth/login@            — returns a signed HS256 JWT on valid credentials
  * @GET /dashboard/summary@      — returns aggregated dashboard state (JWT required)
  * @GET /orders@                 — paginated list of orders (JWT required)
  * @GET /orders/{identifier}@    — single order detail (JWT required)
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
import Presentation.Handler.Orders (
  OrderDetailResponse,
  OrderListResponse,
  getOrderByIdentifierHandler,
  getOrdersHandler,
 )
import Servant (
  Capture,
  Get,
  Header,
  JSON,
  Post,
  Proxy (..),
  QueryParam,
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

type OrdersAPI =
  "orders"
    :> Header "Authorization" Text
    :> QueryParam "status" Text
    :> QueryParam "symbol" Text
    :> QueryParam "from" Text
    :> QueryParam "to" Text
    :> QueryParam "limit" Int
    :> QueryParam "cursor" Text
    :> Get '[JSON] OrderListResponse
    :<|> "orders"
      :> Capture "identifier" Text
      :> Header "Authorization" Text
      :> Get '[JSON] OrderDetailResponse

type BffAPI = BffPublicAPI :<|> BffProtectedAPI :<|> OrdersAPI

bffApiProxy :: Proxy BffAPI
bffApiProxy = Proxy

-- ---------------------------------------------------------------------------
-- Server
-- ---------------------------------------------------------------------------

{- | Wire 'BffAPI' to its handlers.

  * @POST /auth/login@            → 'loginHandler'
  * @GET /dashboard/summary@      → 'getDashboardSummaryHandler'
  * @GET /orders@                 → 'getOrdersHandler'
  * @GET /orders/{identifier}@    → 'getOrderByIdentifierHandler'
-}
bffServer :: AppEnv -> Server BffAPI
bffServer appEnvironment =
  loginHandler appEnvironment
    :<|> getDashboardSummaryHandler appEnvironment
    :<|> getOrdersHandler appEnvironment
    :<|> getOrderByIdentifierHandler appEnvironment
