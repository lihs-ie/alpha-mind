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
  * @PUT /settings/strategy@                  — updates strategy settings (JWT required, admin)
  * @GET /compliance/controls@                — returns compliance controls (JWT required)
  * @PUT /compliance/controls@                — updates compliance controls (JWT required, admin)
  * @GET /insights@                           — paginated list of insight records (JWT required)
  * @GET /insights/{identifier}@              — single insight record detail (JWT required)
  * @POST /insights/{identifier}/adopt@       — adopt an insight record (JWT required, insights:write)
  * @POST /insights/{identifier}/reject@      — reject an insight record (JWT required, insights:write)
  * @POST /insights/{identifier}/hypothesize@ — hypothesize from an insight (JWT required, insights:write)
  * @GET /hypotheses@                                     — paginated list of hypotheses (JWT required)
  * @GET /hypotheses/{identifier}@                        — single hypothesis detail (JWT required)
  * @POST /hypotheses/{identifier}/promote@               — promote hypothesis to live (JWT required, hypotheses:decide)
  * @POST /hypotheses/{identifier}/reject@                — reject hypothesis (JWT required, hypotheses:decide)
  * @POST /hypotheses/{identifier}/retest@                — request hypothesis retest (JWT required, hypotheses:retest)
  * @PUT /hypotheses/{identifier}/mnpi-self-declaration@  — update MNPI self-declaration (JWT required, hypotheses:decide)
  * @GET /models/validation@                             — paginated list of model validations (JWT required)
  * @GET /models/validation/{modelVersion}@              — single model validation detail (JWT required)
  * @POST /models/validation/{modelVersion}/approve@     — approve a model validation (JWT required, models:decide)
  * @POST /models/validation/{modelVersion}/reject@      — reject a model validation (JWT required, models:decide)
  * @POST /operations/runtime@                — change runtime state (JWT required)
  * @POST /operations/kill-switch@            — toggle kill switch (JWT required)
  * @POST /commands/run-cycle@                — trigger market collect cycle (JWT required)
  * @POST /commands/run-insight-cycle@        — trigger insight collect cycle (JWT required)
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
import Presentation.Handler.Commands (
  CommandAccepted,
  RunCycleRequest,
  RunInsightCycleRequest,
  handleRunCycle,
  handleRunInsightCycle,
 )
import Presentation.Handler.Dashboard (DashboardSummaryResponse, getDashboardSummaryHandler)
import Presentation.Handler.Hypotheses (
  HypothesisActionResult,
  HypothesisDecisionRequest,
  HypothesisDetailResponse,
  HypothesisListResponse,
  HypothesisMnpiSelfDeclarationUpdateRequest,
  HypothesisRejectRequest,
  HypothesisRetestAccepted,
  getHypothesesHandler,
  getHypothesisByIdentifierHandler,
  promoteHypothesisHandler,
  rejectHypothesisHandler,
  retestHypothesisHandler,
  updateHypothesisMnpiHandler,
 )
import Presentation.Handler.Insights (
  HypothesizeRequest,
  InsightActionResult,
  InsightDecisionRequest,
  InsightDetailResponse,
  InsightHypothesizeAccepted,
  InsightListResponse,
  adoptInsightHandler,
  getInsightByIdentifierHandler,
  getInsightsHandler,
  hypothesizeInsightHandler,
  rejectInsightHandler,
 )
import Presentation.Handler.ModelValidations (
  ModelActionResult,
  ModelDecisionRequest,
  ModelValidationDetailResponse,
  ModelValidationListResponse,
  approveModelValidationHandler,
  getModelValidationByVersionHandler,
  getModelValidationsHandler,
  rejectModelValidationHandler,
 )
import Presentation.Handler.Operations (
  KillSwitchRequest,
  OperationResult,
  RuntimeOperationRequest,
  handleChangeRuntime,
  handleToggleKillSwitch,
 )
import Presentation.Handler.Orders (
  ApproveOrderRequest,
  OrderActionResult,
  OrderDetailResponse,
  OrderListResponse,
  OrderRetryAccepted,
  RejectOrderRequest,
  approveOrderHandler,
  getOrderByIdentifierHandler,
  getOrdersHandler,
  rejectOrderHandler,
  retryOrderHandler,
 )
import Presentation.Handler.Settings (
  ComplianceControlsResponse,
  ComplianceControlsUpdateRequest,
  StrategySettingsResponse,
  StrategySettingsUpdateRequest,
  UpdateResult,
  getComplianceControlsHandler,
  getSettingsStrategyHandler,
  putComplianceControlsHandler,
  putSettingsStrategyHandler,
 )
import Servant (
  Capture,
  Get,
  Header,
  JSON,
  Post,
  PostAccepted,
  Proxy (..),
  Put,
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
    :<|> "orders"
      :> Capture "identifier" Text
      :> "approve"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] ApproveOrderRequest
      :> Post '[JSON] OrderActionResult
    :<|> "orders"
      :> Capture "identifier" Text
      :> "reject"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] RejectOrderRequest
      :> Post '[JSON] OrderActionResult
    :<|> "orders"
      :> Capture "identifier" Text
      :> "retry"
      :> Header "Authorization" Text
      :> PostAccepted '[JSON] OrderRetryAccepted

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
    :<|> "settings"
      :> "strategy"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] StrategySettingsUpdateRequest
      :> Put '[JSON] UpdateResult
    :<|> "compliance"
      :> "controls"
      :> Header "Authorization" Text
      :> Get '[JSON] ComplianceControlsResponse
    :<|> "compliance"
      :> "controls"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] ComplianceControlsUpdateRequest
      :> Put '[JSON] UpdateResult

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
    :<|> "insights"
      :> Capture "identifier" Text
      :> "adopt"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] InsightDecisionRequest
      :> Post '[JSON] InsightActionResult
    :<|> "insights"
      :> Capture "identifier" Text
      :> "reject"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] InsightDecisionRequest
      :> Post '[JSON] InsightActionResult
    :<|> "insights"
      :> Capture "identifier" Text
      :> "hypothesize"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] HypothesizeRequest
      :> PostAccepted '[JSON] InsightHypothesizeAccepted

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
    :<|> "hypotheses"
      :> Capture "identifier" Text
      :> "promote"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] HypothesisDecisionRequest
      :> Post '[JSON] HypothesisActionResult
    :<|> "hypotheses"
      :> Capture "identifier" Text
      :> "reject"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] HypothesisRejectRequest
      :> Post '[JSON] HypothesisActionResult
    :<|> "hypotheses"
      :> Capture "identifier" Text
      :> "retest"
      :> Header "Authorization" Text
      :> PostAccepted '[JSON] HypothesisRetestAccepted
    :<|> "hypotheses"
      :> Capture "identifier" Text
      :> "mnpi-self-declaration"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] HypothesisMnpiSelfDeclarationUpdateRequest
      :> Put '[JSON] HypothesisActionResult

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
    :<|> "models"
      :> "validation"
      :> Capture "modelVersion" Text
      :> "approve"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] ModelDecisionRequest
      :> Post '[JSON] ModelActionResult
    :<|> "models"
      :> "validation"
      :> Capture "modelVersion" Text
      :> "reject"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] ModelDecisionRequest
      :> Post '[JSON] ModelActionResult

type OperationsAPI =
  "operations"
    :> "runtime"
    :> Header "Authorization" Text
    :> ReqBody '[JSON] RuntimeOperationRequest
    :> Post '[JSON] OperationResult
    :<|> "operations"
      :> "kill-switch"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] KillSwitchRequest
      :> Post '[JSON] OperationResult

type CommandsAPI =
  "commands"
    :> "run-cycle"
    :> Header "Authorization" Text
    :> ReqBody '[JSON] RunCycleRequest
    :> PostAccepted '[JSON] CommandAccepted
    :<|> "commands"
      :> "run-insight-cycle"
      :> Header "Authorization" Text
      :> ReqBody '[JSON] RunInsightCycleRequest
      :> PostAccepted '[JSON] CommandAccepted

type BffAPI =
  BffPublicAPI
    :<|> BffProtectedAPI
    :<|> OrdersAPI
    :<|> AuditAPI
    :<|> SettingsAPI
    :<|> InsightsAPI
    :<|> HypothesesAPI
    :<|> ModelsValidationAPI
    :<|> OperationsAPI
    :<|> CommandsAPI

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
  * @PUT /settings/strategy@                 → 'putSettingsStrategyHandler'
  * @GET /compliance/controls@               → 'getComplianceControlsHandler'
  * @PUT /compliance/controls@               → 'putComplianceControlsHandler'
  * @GET /insights@                          → 'getInsightsHandler'
  * @GET /insights/{identifier}@             → 'getInsightByIdentifierHandler'
  * @POST /insights/{identifier}/adopt@      → 'adoptInsightHandler'
  * @POST /insights/{identifier}/reject@     → 'rejectInsightHandler'
  * @POST /insights/{identifier}/hypothesize@ → 'hypothesizeInsightHandler'
  * @GET /hypotheses@                                    → 'getHypothesesHandler'
  * @GET /hypotheses/{identifier}@                       → 'getHypothesisByIdentifierHandler'
  * @POST /hypotheses/{identifier}/promote@              → 'promoteHypothesisHandler'
  * @POST /hypotheses/{identifier}/reject@               → 'rejectHypothesisHandler'
  * @POST /hypotheses/{identifier}/retest@               → 'retestHypothesisHandler'
  * @PUT /hypotheses/{identifier}/mnpi-self-declaration@ → 'updateHypothesisMnpiHandler'
  * @GET /models/validation@                            → 'getModelValidationsHandler'
  * @GET /models/validation/{modelVersion}@             → 'getModelValidationByVersionHandler'
  * @POST /models/validation/{modelVersion}/approve@    → 'approveModelValidationHandler'
  * @POST /models/validation/{modelVersion}/reject@     → 'rejectModelValidationHandler'
  * @POST /operations/runtime@               → 'handleChangeRuntime'
  * @POST /operations/kill-switch@           → 'handleToggleKillSwitch'
  * @POST /commands/run-cycle@               → 'handleRunCycle'
  * @POST /commands/run-insight-cycle@       → 'handleRunInsightCycle'
-}
bffServer :: AppEnv -> Server BffAPI
bffServer appEnvironment =
  loginHandler appEnvironment
    :<|> getDashboardSummaryHandler appEnvironment
    :<|> ( getOrdersHandler appEnvironment
             :<|> getOrderByIdentifierHandler appEnvironment
             :<|> approveOrderHandler appEnvironment
             :<|> rejectOrderHandler appEnvironment
             :<|> retryOrderHandler appEnvironment
         )
    :<|> (getAuditLogsHandler appEnvironment :<|> getAuditLogByIdentifierHandler appEnvironment)
    :<|> ( getSettingsStrategyHandler appEnvironment
             :<|> putSettingsStrategyHandler appEnvironment
             :<|> getComplianceControlsHandler appEnvironment
             :<|> putComplianceControlsHandler appEnvironment
         )
    :<|> ( getInsightsHandler appEnvironment
             :<|> getInsightByIdentifierHandler appEnvironment
             :<|> adoptInsightHandler appEnvironment
             :<|> rejectInsightHandler appEnvironment
             :<|> hypothesizeInsightHandler appEnvironment
         )
    :<|> ( getHypothesesHandler appEnvironment
             :<|> getHypothesisByIdentifierHandler appEnvironment
             :<|> promoteHypothesisHandler appEnvironment
             :<|> rejectHypothesisHandler appEnvironment
             :<|> retestHypothesisHandler appEnvironment
             :<|> updateHypothesisMnpiHandler appEnvironment
         )
    :<|> ( getModelValidationsHandler appEnvironment
             :<|> getModelValidationByVersionHandler appEnvironment
             :<|> approveModelValidationHandler appEnvironment
             :<|> rejectModelValidationHandler appEnvironment
         )
    :<|> (handleChangeRuntime appEnvironment :<|> handleToggleKillSwitch appEnvironment)
    :<|> (handleRunCycle appEnvironment :<|> handleRunInsightCycle appEnvironment)
