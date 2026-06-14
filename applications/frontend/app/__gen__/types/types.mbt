///| Auto-generated types for island props
///| Re-exports Props structs from client packages

///| Props type from @client
pub(all) struct DashboardOperationsProps {
  bff_base_url : String
  initial_runtime_state : String
  initial_kill_switch_enabled : Bool
} derive(ToJson, FromJson)

///| Props type from @client
pub(all) struct LoginFormProps {
  bff_base_url : String
} derive(ToJson, FromJson)

// =============================================================================
// ComponentRef Factory Functions
// =============================================================================

///|
///| Create ComponentRef for dashboard_operations component
pub fn dashboard_operations(
  props : DashboardOperationsProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[DashboardOperationsProps] {
  { url: "/static/dashboard_operations.js", props, wc: false, trigger }
}

///|
///| Create ComponentRef for login_form component
pub fn login_form(
  props : LoginFormProps,
  trigger~ : @luna.Trigger = @luna.TriggerType::Load,
) -> @luna.ComponentRef[LoginFormProps] {
  { url: "/static/login_form.js", props, wc: false, trigger }
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

