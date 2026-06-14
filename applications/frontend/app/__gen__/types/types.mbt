///| Auto-generated types for island props
///| Re-exports Props structs from client packages

///| Props type from @client
pub(all) struct AuditRowProps {
  identifier : String
  occurred_at : String
  event_type : String
  service : String
  result : String
  trace : String
} derive(ToJson, FromJson)

///| Props type from @client
pub(all) struct AuditSearchProps {
  bff_base_url : String
  initial_logs : Array[AuditRowProps]
} derive(ToJson, FromJson)

///| Props type from @client
pub(all) struct DashboardOperationsProps {
  bff_base_url : String
  initial_runtime_state : String
  initial_kill_switch_enabled : Bool
} derive(ToJson, FromJson)

///| Props type from @client
pub(all) struct InsightRowProps {
  identifier : String
  source_type : String
  summary : String
  source_url : String
  collected_at : String
  signal_class : String
  so_what_score : Double
} derive(ToJson, FromJson)

///| Props type from @client
pub(all) struct InsightsActionsProps {
  bff_base_url : String
  initial_insights : Array[InsightRowProps]
  initial_next_cursor : String
} derive(ToJson, FromJson)

///| Props type from @client
pub(all) struct LoginFormProps {
  bff_base_url : String
} derive(ToJson, FromJson)

///| Props type from @client
pub(all) struct ModelValidationRowProps {
  model_version : String
  status : String
  degradation_flag : String
  created_at : String
} derive(ToJson, FromJson)

///| Props type from @client
pub(all) struct ModelsActionsProps {
  bff_base_url : String
  initial_models : Array[ModelValidationRowProps]
} derive(ToJson, FromJson)

///| Props type from @client
pub(all) struct OrderRowProps {
  identifier : String
  symbol : String
  side : String
  qty : Double
  status : String
  created_at : String
} derive(ToJson, FromJson)

///| Props type from @client
pub(all) struct OrdersActionsProps {
  bff_base_url : String
  initial_orders : Array[OrderRowProps]
  initial_kill_switch_enabled : Bool
} derive(ToJson, FromJson)

///| Props type from @client
pub(all) struct BlackoutWindowProps {
  symbol : String
  start_at : String
  end_at : String
  action_reason_code : String
} derive(ToJson, FromJson)

///| Props type from @client
pub(all) struct StrategyFormProps {
  bff_base_url : String
  initial_market : String
  initial_rebalance_frequency : String
  initial_symbols : Array[String]
  initial_daily_loss_limit : Double
  initial_position_concentration_limit : Double
  initial_daily_order_limit : Int
  initial_restricted_symbols : Array[String]
  initial_blackout_windows : Array[BlackoutWindowProps]
} derive(ToJson, FromJson)

// =============================================================================
// ComponentRef Factory Functions
// =============================================================================

///|
///| Create ComponentRef for audit_row component
pub fn audit_row(
  props : AuditRowProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[AuditRowProps] {
  { url: "/static/audit_row.js", props, wc: false, trigger }
}

///|
///| Create ComponentRef for audit_search component
pub fn audit_search(
  props : AuditSearchProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[AuditSearchProps] {
  { url: "/static/audit_search.js", props, wc: false, trigger }
}

///|
///| Create ComponentRef for dashboard_operations component
pub fn dashboard_operations(
  props : DashboardOperationsProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[DashboardOperationsProps] {
  { url: "/static/dashboard_operations.js", props, wc: false, trigger }
}

///|
///| Create ComponentRef for insight_row component
pub fn insight_row(
  props : InsightRowProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[InsightRowProps] {
  { url: "/static/insight_row.js", props, wc: false, trigger }
}

///|
///| Create ComponentRef for insights_actions component
pub fn insights_actions(
  props : InsightsActionsProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[InsightsActionsProps] {
  { url: "/static/insights_actions.js", props, wc: false, trigger }
}

///|
///| Create ComponentRef for login_form component
pub fn login_form(
  props : LoginFormProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[LoginFormProps] {
  { url: "/static/login_form.js", props, wc: false, trigger }
}

///|
///| Create ComponentRef for model_validation_row component
pub fn model_validation_row(
  props : ModelValidationRowProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[ModelValidationRowProps] {
  { url: "/static/model_validation_row.js", props, wc: false, trigger }
}

///|
///| Create ComponentRef for models_actions component
pub fn models_actions(
  props : ModelsActionsProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[ModelsActionsProps] {
  { url: "/static/models_actions.js", props, wc: false, trigger }
}

///|
///| Create ComponentRef for order_row component
pub fn order_row(
  props : OrderRowProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[OrderRowProps] {
  { url: "/static/order_row.js", props, wc: false, trigger }
}

///|
///| Create ComponentRef for orders_actions component
pub fn orders_actions(
  props : OrdersActionsProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[OrdersActionsProps] {
  { url: "/static/orders_actions.js", props, wc: false, trigger }
}

///|
///| Create ComponentRef for blackout_window component
pub fn blackout_window(
  props : BlackoutWindowProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[BlackoutWindowProps] {
  { url: "/static/blackout_window.js", props, wc: false, trigger }
}

///|
///| Create ComponentRef for strategy_form component
pub fn strategy_form(
  props : StrategyFormProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[StrategyFormProps] {
  { url: "/static/strategy_form.js", props, wc: false, trigger }
}

// =============================================================================
// Route Path Constants
// =============================================================================

///|
/// Route path: /api/health
pub let route_api_health : String = "/api/health"

///|
/// Route path: /login
pub let route_login : String = "/login"

///|
/// Route path: /dashboard
pub let route_dashboard : String = "/dashboard"

///|
/// Route path: /settings/strategy
pub let route_settings_strategy : String = "/settings/strategy"

///|
/// Route path: /orders
pub let route_orders : String = "/orders"

///|
/// Route path: /audit
pub let route_audit : String = "/audit"

///|
/// Route path: /models/validation
pub let route_models_validation : String = "/models/validation"

///|
/// Route path: /insights
pub let route_insights : String = "/insights"

// =============================================================================
// Link Builder Functions
// =============================================================================

///|
/// Link builder for route: /api/health
pub fn link_api_health() -> String {
  "/api/health"
}

///|
/// Link builder for route: /login
pub fn link_login() -> String {
  "/login"
}

///|
/// Link builder for route: /dashboard
pub fn link_dashboard() -> String {
  "/dashboard"
}

///|
/// Link builder for route: /settings/strategy
pub fn link_settings_strategy() -> String {
  "/settings/strategy"
}

///|
/// Link builder for route: /orders
pub fn link_orders() -> String {
  "/orders"
}

///|
/// Link builder for route: /audit
pub fn link_audit() -> String {
  "/audit"
}

///|
/// Link builder for route: /models/validation
pub fn link_models_validation() -> String {
  "/models/validation"
}

///|
/// Link builder for route: /insights
pub fn link_insights() -> String {
  "/insights"
}

