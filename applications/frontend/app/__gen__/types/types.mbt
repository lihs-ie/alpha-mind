///| Auto-generated types for island props
///| Re-exports Props structs from client packages

///| Props type from @client
pub(all) struct LoginFormProps {
  bff_base_url : String
} derive(ToJson, FromJson)

// =============================================================================
// ComponentRef Factory Functions
// =============================================================================

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

