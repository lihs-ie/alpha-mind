{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

{- | Servant API type definition for the BFF service.

Defines 'BffAPI' as the business API (excluding the standard health
endpoints which are added by 'App.Bootstrap.mkApplication').

Endpoints:
  * @POST /auth/login@                        — returns a signed HS256 JWT on valid credentials
  * @GET /dashboard/summary@                  — returns aggregated dashboard state (JWT required)
  * @GET /orders@                             — paginated list of orders (JWT required)
  * @GET /orders/{identifier}@                — single order detail (JWT required)
  * @GET /audit@                              — paginated list of audit logs (JWT required)
  * @GET /audit/{identifier}@                 — single audit log detail (JWT required)
  * @GET /settings/strategy@                  — returns strategy settings (JWT required)
  * @GET /compliance/controls@                — returns compliance controls (JWT required)
  * @GET /insights@                           — paginated list of insight records (JWT required)
  * @GET /insights/{identifier}@              — single insight record detail (JWT required)
  * @GET /hypotheses@                         — paginated list of hypotheses (JWT required)
  * @GET /hypotheses/{identifier}@            — single hypothesis detail (JWT required)
  * @GET /models/validation@                  — paginated list of model validations (JWT required)
  * @GET /models/validation/{modelVersion}@   — single model validation detail (JWT required)
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
import Presentation.Handler.Audit (
  AuditDetailResponse,
  AuditListResponse,
  getAuditLogByIdentifierHandler,
  getAuditLogsHandler,
 )
import Presentation.Handler.Auth (LoginRequest, LoginResponse, loginHandler)
import Presentation.Handler.Dashboard (DashboardSummaryResponse, getDashboardSummaryHandler)
import Presentation.Handler.Hypotheses (
  HypothesisDetailResponse,
  HypothesisListResponse,
  getHypothesesHandler,
  getHypothesisByIdentifierHandler,
 )
import Presentation.Handler.Insights (
  InsightDetailResponse,
  InsightListResponse,
  getInsightByIdentifierHandler,
  getInsightsHandler,
 )
import Presentation.Handler.ModelValidations (
  ModelValidationDetailResponse,
  ModelValidationListResponse,
  getModelValidationByVersionHandler,
  getModelValidationsHandler,
 )
import Presentation.Handler.Orders (
  OrderDetailResponse,
  OrderListResponse,
  getOrderByIdentifierHandler,
  getOrdersHandler,
 )
import Presentation.Handler.Settings (
  ComplianceControlsResponse,
  StrategySettingsResponse,
  getComplianceControlsHandler,
  getSettingsStrategyHandler,
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

type AuditAPI =
  "audit"
    :> Header "Authorization" Text
    :> QueryParam "trace" Text
    :> QueryParam "eventType" Text
    :> QueryParam "from" Text
    :> QueryParam "to" Text
    :> QueryParam "limit" Int
    :> QueryParam "cursor" Text
    :> Get '[JSON] AuditListResponse
    :<|> "audit"
      :> Capture "identifier" Text
      :> Header "Authorization" Text
      :> Get '[JSON] AuditDetailResponse

type SettingsAPI =
  "settings"
    :> "strategy"
    :> Header "Authorization" Text
    :> Get '[JSON] StrategySettingsResponse
    :<|> "compliance"
      :> "controls"
      :> Header "Authorization" Text
      :> Get '[JSON] ComplianceControlsResponse

type InsightsAPI =
  "insights"
    :> Header "Authorization" Text
    :> QueryParam "symbol" Text
    :> QueryParam "from" Text
    :> QueryParam "to" Text
    :> QueryParam "limit" Int
    :> QueryParam "cursor" Text
    :> Get '[JSON] InsightListResponse
    :<|> "insights"
      :> Capture "identifier" Text
      :> Header "Authorization" Text
      :> Get '[JSON] InsightDetailResponse

type HypothesesAPI =
  "hypotheses"
    :> Header "Authorization" Text
    :> QueryParam "status" Text
    :> QueryParam "limit" Int
    :> QueryParam "cursor" Text
    :> Get '[JSON] HypothesisListResponse
    :<|> "hypotheses"
      :> Capture "identifier" Text
      :> Header "Authorization" Text
      :> Get '[JSON] HypothesisDetailResponse

type ModelsValidationAPI =
  "models"
    :> "validation"
    :> Header "Authorization" Text
    :> QueryParam "status" Text
    :> QueryParam "degradationFlag" Text
    :> QueryParam "limit" Int
    :> QueryParam "cursor" Text
    :> Get '[JSON] ModelValidationListResponse
    :<|> "models"
      :> "validation"
      :> Capture "modelVersion" Text
      :> Header "Authorization" Text
      :> Get '[JSON] ModelValidationDetailResponse

type BffAPI =
  BffPublicAPI
    :<|> BffProtectedAPI
    :<|> OrdersAPI
    :<|> AuditAPI
    :<|> SettingsAPI
    :<|> InsightsAPI
    :<|> HypothesesAPI
    :<|> ModelsValidationAPI

bffApiProxy :: Proxy BffAPI
bffApiProxy = Proxy

-- ---------------------------------------------------------------------------
-- Server
-- ---------------------------------------------------------------------------

{- | Wire 'BffAPI' to its handlers.

  * @POST /auth/login@                       → 'loginHandler'
  * @GET /dashboard/summary@                 → 'getDashboardSummaryHandler'
  * @GET /orders@                            → 'getOrdersHandler'
  * @GET /orders/{identifier}@               → 'getOrderByIdentifierHandler'
  * @GET /audit@                             → 'getAuditLogsHandler'
  * @GET /audit/{identifier}@                → 'getAuditLogByIdentifierHandler'
  * @GET /settings/strategy@                 → 'getSettingsStrategyHandler'
  * @GET /compliance/controls@               → 'getComplianceControlsHandler'
  * @GET /insights@                          → 'getInsightsHandler'
  * @GET /insights/{identifier}@             → 'getInsightByIdentifierHandler'
  * @GET /hypotheses@                        → 'getHypothesesHandler'
  * @GET /hypotheses/{identifier}@           → 'getHypothesisByIdentifierHandler'
  * @GET /models/validation@                 → 'getModelValidationsHandler'
  * @GET /models/validation/{modelVersion}@  → 'getModelValidationByVersionHandler'
-}
bffServer :: AppEnv -> Server BffAPI
bffServer appEnvironment =
  loginHandler appEnvironment
    :<|> getDashboardSummaryHandler appEnvironment
    :<|> (getOrdersHandler appEnvironment :<|> getOrderByIdentifierHandler appEnvironment)
    :<|> (getAuditLogsHandler appEnvironment :<|> getAuditLogByIdentifierHandler appEnvironment)
    :<|> (getSettingsStrategyHandler appEnvironment :<|> getComplianceControlsHandler appEnvironment)
    :<|> (getInsightsHandler appEnvironment :<|> getInsightByIdentifierHandler appEnvironment)
    :<|> (getHypothesesHandler appEnvironment :<|> getHypothesisByIdentifierHandler appEnvironment)
    :<|> (getModelValidationsHandler appEnvironment :<|> getModelValidationByVersionHandler appEnvironment)
