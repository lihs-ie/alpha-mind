///| ACL layer — BFF API adapter for the frontend bounded context.
///|
///| This package converts BFF JSON responses (from openapi.yaml contract) into
///| frontend domain models. All functions are PURE transformations; no HTTP I/O
///| lives here. HTTP calls are issued by page handlers via @core.Any JS FFI.
///|
///| Contract source: documents/外部設計/api/openapi.yaml
///|
///| Design rules:
///|   - ACL-001: DTOs must exactly mirror openapi.yaml schema field names.
///|   - ACL-002: conversions must never panic; unknown values map to safe defaults.
///|   - ACL-003: ProblemDetail parsing delegates to @infra.parse_reason_code.
///|   - ACL-004: no BFF DTO types are leaked beyond this package boundary
///|               (domain types are returned to callers).

// ============================================================================
// BffClient — runtime context for making BFF HTTP calls
// ============================================================================

/// Runtime context for BFF API calls.
/// Holds the base URL and the current JWT access token.
/// Created by page handlers once the token is available from JwtTokenStore.
pub struct BffClient {
  /// Base URL of the BFF API (e.g. "https://api.alpha-mind.dev").
  baseUrl : String
  /// Raw JWT access token. Empty string if unauthenticated.
  accessToken : String
}

/// Create a BffClient.
pub fn BffClient::new(base_url : String, access_token : String) -> BffClient {
  { baseUrl: base_url, accessToken: access_token }
}

/// Build the Authorization header value from the stored token.
pub fn BffClient::authorization_header(self : BffClient) -> String {
  "Bearer " + self.accessToken
}

// ============================================================================
// AclError — error type returned by ACL conversion functions
// ============================================================================

/// Error variants returned when ACL conversion fails.
pub(all) enum AclError {
  /// The BFF returned an RFC 9457 Problem Detail.
  ApiProblem(@infra.ProblemDetail)
  /// Required field missing in the JSON response.
  MissingField(String)
  /// Unexpected field value (e.g. unknown enum).
  UnexpectedValue(String)
} derive(Show)

// ============================================================================
// JSON helper utilities
// ============================================================================

/// Extract a String field from a @core.Any JSON object.
/// Returns AclError::MissingField if the key is absent or not a String.
pub fn get_string(json : @core.Any, key : String) -> Result[String, AclError] {
  let value = json._get(key)
  if @core.is_nullish(value) {
    Err(AclError::MissingField("Missing field: " + key))
  } else {
    let s : String = value.cast()
    Ok(s)
  }
}

/// Extract an optional String field (returns None when absent/null).
pub fn get_string_opt(json : @core.Any, key : String) -> String? {
  let value = json._get(key)
  if @core.is_nullish(value) {
    None
  } else {
    let s : String = value.cast()
    Some(s)
  }
}

/// Extract an Int field from a @core.Any JSON object.
pub fn get_int(json : @core.Any, key : String) -> Result[Int, AclError] {
  let value = json._get(key)
  if @core.is_nullish(value) {
    Err(AclError::MissingField("Missing field: " + key))
  } else {
    let n : Int = value.cast()
    Ok(n)
  }
}

/// Extract a Double field from a @core.Any JSON object.
pub fn get_double(json : @core.Any, key : String) -> Result[Double, AclError] {
  let value = json._get(key)
  if @core.is_nullish(value) {
    Err(AclError::MissingField("Missing field: " + key))
  } else {
    let n : Double = value.cast()
    Ok(n)
  }
}

/// Extract a Bool field from a @core.Any JSON object.
pub fn get_bool(json : @core.Any, key : String) -> Result[Bool, AclError] {
  let value = json._get(key)
  if @core.is_nullish(value) {
    Err(AclError::MissingField("Missing field: " + key))
  } else {
    let b : Bool = value.cast()
    Ok(b)
  }
}

/// Extract an Array field from a @core.Any JSON object.
pub fn get_array(
  json : @core.Any,
  key : String
) -> Result[Array[@core.Any], AclError] {
  let value = json._get(key)
  if @core.is_nullish(value) {
    Err(AclError::MissingField("Missing field: " + key))
  } else {
    let arr : Array[@core.Any] = value.cast()
    Ok(arr)
  }
}

// ============================================================================
// Problem Detail — RFC 9457 parsing (ACL-003)
// ============================================================================

/// Parse a BFF Problem Detail JSON object into an AclError::ApiProblem.
/// Delegates reason code parsing to @infra.parse_reason_code.
pub fn parse_problem_detail(json : @core.Any) -> AclError {
  let status = match get_int(json, "status") {
    Ok(s) => s
    Err(_) => 500
  }
  let title = match get_string(json, "title") {
    Ok(t) => t
    Err(_) => "Unknown error"
  }
  let detail = match get_string(json, "detail") {
    Ok(d) => d
    Err(_) => ""
  }
  let trace = get_string_opt(json, "trace")
  let raw_reason_code = match get_string(json, "reasonCode") {
    Ok(rc) => rc
    Err(_) => "INTERNAL_ERROR"
  }
  let retryable = match get_bool(json, "retryable") {
    Ok(r) => r
    Err(_) => @infra.is_retryable_status(status)
  }
  let problem = @infra.new_problem_detail(
    status,
    title,
    detail,
    trace,
    raw_reason_code,
    retryable,
  )
  AclError::ApiProblem(problem)
}

// ============================================================================
// Auth — /auth/login (POST)
// Schema: LoginResponse → LoginAclOutput
// ============================================================================

/// DTO for the User object within LoginResponse.
struct UserDto {
  identifier : String
  email : String
  role : String
  permissions : Array[String]
}

/// DTO for the LoginResponse from POST /auth/login.
struct LoginResponseDto {
  accessToken : String
  tokenType : String
  expiresIn : Int
  user : UserDto
}

/// Parse a UserDto from raw JSON.
fn parse_user_dto(json : @core.Any) -> Result[UserDto, AclError] {
  let identifier = match get_string(json, "identifier") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let email = match get_string(json, "email") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let role = match get_string(json, "role") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let permissions_raw = match get_array(json, "permissions") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let permissions : Array[String] = permissions_raw.map(fn(p) {
    let s : String = p.cast()
    s
  })
  Ok({ identifier, email, role, permissions })
}

/// Parse a LoginResponseDto from raw JSON.
fn parse_login_response_dto(
  json : @core.Any
) -> Result[LoginResponseDto, AclError] {
  let access_token = match get_string(json, "accessToken") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let token_type = match get_string(json, "tokenType") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let expires_in = match get_int(json, "expiresIn") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let user_json = json._get("user")
  let user = match parse_user_dto(user_json) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok({
    accessToken: access_token,
    tokenType: token_type,
    expiresIn: expires_in,
    user,
  })
}

/// Convert a role string to the domain Role enum.
/// Unknown values default to Viewer (ACL-002).
pub fn parse_role(raw : String) -> @session.Role {
  match raw {
    "admin" => @session.Role::Admin
    _ => @session.Role::Viewer
  }
}

/// Output of a successful login ACL conversion.
pub struct LoginAclOutput {
  /// Subject (user identifier) extracted from the response.
  subject : String
  /// Email extracted from the response.
  email : String
  /// Domain Role.
  role : @session.Role
  /// Domain Permission array.
  permissions : Array[@session.Permission]
  /// Raw access token (to be stored in JwtTokenStore).
  accessToken : String
  /// Token type (should be "Bearer").
  tokenType : String
  /// Token lifetime in seconds.
  expiresIn : Int
}

/// Convert a BFF LoginResponse JSON into the ACL output.
pub fn convert_login_response(
  json : @core.Any
) -> Result[LoginAclOutput, AclError] {
  let dto = match parse_login_response_dto(json) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let role = parse_role(dto.user.role)
  let permissions = dto.user.permissions.map(fn(p) {
    @session.Permission::{ value: p }
  })
  Ok({
    subject: dto.user.identifier,
    email: dto.user.email,
    role,
    permissions,
    accessToken: dto.accessToken,
    tokenType: dto.tokenType,
    expiresIn: dto.expiresIn,
  })
}

// ============================================================================
// Dashboard — /dashboard/summary (GET)
// Schema: DashboardSummary → DashboardView
// ============================================================================

/// DTO for DashboardSummary.
struct DashboardSummaryDto {
  pnlToday : Double
  pnlTotal : Double
  maxDrawdown : Double
  runtimeState : String
  killSwitchEnabled : Bool
  latestSignalAt : String
}

/// Parse a DashboardSummaryDto from raw JSON.
fn parse_dashboard_summary_dto(
  json : @core.Any
) -> Result[DashboardSummaryDto, AclError] {
  let pnl_today = match get_double(json, "pnlToday") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let pnl_total = match get_double(json, "pnlTotal") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let max_drawdown = match get_double(json, "maxDrawdown") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let runtime_state = match get_string(json, "runtimeState") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let kill_switch_enabled = match get_bool(json, "killSwitchEnabled") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let latest_signal_at = match get_string(json, "latestSignalAt") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok({
    pnlToday: pnl_today,
    pnlTotal: pnl_total,
    maxDrawdown: max_drawdown,
    runtimeState: runtime_state,
    killSwitchEnabled: kill_switch_enabled,
    latestSignalAt: latest_signal_at,
  })
}

/// Domain view model for the dashboard summary.
pub struct DashboardView {
  pnlToday : Double
  pnlTotal : Double
  maxDrawdown : Double
  runtimeState : String
  killSwitchEnabled : Bool
  latestSignalAt : String
} derive(Show)

/// Convert a BFF DashboardSummary JSON into a DashboardView domain model.
pub fn convert_dashboard_summary(
  json : @core.Any
) -> Result[DashboardView, AclError] {
  let dto = match parse_dashboard_summary_dto(json) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok({
    pnlToday: dto.pnlToday,
    pnlTotal: dto.pnlTotal,
    maxDrawdown: dto.maxDrawdown,
    runtimeState: dto.runtimeState,
    killSwitchEnabled: dto.killSwitchEnabled,
    latestSignalAt: dto.latestSignalAt,
  })
}

// ============================================================================
// Orders — /orders (GET), /orders/{identifier} (GET)
// Schema: OrderListResponse, OrderSummary → OrderListView
// ============================================================================

/// DTO for an OrderSummary item.
struct OrderSummaryDto {
  identifier : String
  symbol : String
  side : String
  qty : Double
  status : String
  createdAt : String
}

/// Parse an OrderSummaryDto from raw JSON.
fn parse_order_summary_dto(
  json : @core.Any
) -> Result[OrderSummaryDto, AclError] {
  let identifier = match get_string(json, "identifier") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let symbol = match get_string(json, "symbol") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let side = match get_string(json, "side") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let qty = match get_double(json, "qty") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let status = match get_string(json, "status") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let created_at = match get_string(json, "createdAt") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok({ identifier, symbol, side, qty, status, createdAt: created_at })
}

/// Domain view model for a single order item.
pub(all) struct OrderView {
  identifier : String
  symbol : String
  side : String
  qty : Double
  status : String
  createdAt : String
} derive(Show)

/// Output of orders list conversion.
pub(all) struct OrderListView {
  items : Array[OrderView]
  nextCursor : String?
} derive(Show)

/// Convert a BFF OrderListResponse JSON into an OrderListView.
pub fn convert_order_list_response(
  json : @core.Any
) -> Result[OrderListView, AclError] {
  let items_raw = match get_array(json, "items") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let items : Array[OrderView] = []
  for item_json in items_raw {
    let dto = match parse_order_summary_dto(item_json) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    items.push({
      identifier: dto.identifier,
      symbol: dto.symbol,
      side: dto.side,
      qty: dto.qty,
      status: dto.status,
      createdAt: dto.createdAt,
    })
  }
  let next_cursor = get_string_opt(json, "nextCursor")
  Ok({ items, nextCursor: next_cursor })
}

/// Convert an OrderListView into ViewItems + Pagination for the domain projection.
pub fn order_list_to_projection(
  view : OrderListView,
  limit : Int
) -> (Array[@projection.ViewItem], @projection.Pagination) {
  let view_items = view.items.map(fn(order) {
    @projection.new_view_item(order.identifier)
  })
  let pagination = @projection.new_pagination(
    view.nextCursor,
    limit,
    not(view.nextCursor.is_empty()),
  )
  (view_items, pagination)
}

// ============================================================================
// Audit — /audit (GET), /audit/{identifier} (GET)
// Schema: AuditListResponse, AuditSummary → AuditListView
// ============================================================================

/// DTO for an AuditSummary item.
struct AuditSummaryDto {
  identifier : String
  occurredAt : String
  eventType : String
  service : String
  result : String
  trace : String
}

/// Parse an AuditSummaryDto from raw JSON.
fn parse_audit_summary_dto(
  json : @core.Any
) -> Result[AuditSummaryDto, AclError] {
  let identifier = match get_string(json, "identifier") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let occurred_at = match get_string(json, "occurredAt") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let event_type = match get_string(json, "eventType") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let service = match get_string(json, "service") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let result = match get_string(json, "result") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let trace = match get_string(json, "trace") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok({
    identifier,
    occurredAt: occurred_at,
    eventType: event_type,
    service,
    result,
    trace,
  })
}

/// Domain view model for a single audit log entry.
pub(all) struct AuditView {
  identifier : String
  occurredAt : String
  eventType : String
  service : String
  result : String
  trace : String
} derive(Show)

/// Output of audit log list conversion.
pub(all) struct AuditListView {
  items : Array[AuditView]
  nextCursor : String?
} derive(Show)

/// Convert a BFF AuditListResponse JSON into an AuditListView.
pub fn convert_audit_list_response(
  json : @core.Any
) -> Result[AuditListView, AclError] {
  let items_raw = match get_array(json, "items") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let items : Array[AuditView] = []
  for item_json in items_raw {
    let dto = match parse_audit_summary_dto(item_json) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    items.push({
      identifier: dto.identifier,
      occurredAt: dto.occurredAt,
      eventType: dto.eventType,
      service: dto.service,
      result: dto.result,
      trace: dto.trace,
    })
  }
  let next_cursor = get_string_opt(json, "nextCursor")
  Ok({ items, nextCursor: next_cursor })
}

/// Convert an AuditListView into ViewItems + Pagination for the domain projection.
pub fn audit_list_to_projection(
  view : AuditListView,
  limit : Int
) -> (Array[@projection.ViewItem], @projection.Pagination) {
  let view_items = view.items.map(fn(entry) {
    @projection.new_view_item(entry.identifier)
  })
  let pagination = @projection.new_pagination(
    view.nextCursor,
    limit,
    not(view.nextCursor.is_empty()),
  )
  (view_items, pagination)
}

// ============================================================================
// Insights — /insights (GET)
// Schema: InsightListResponse, InsightSummary → InsightListView
// ============================================================================

/// DTO for an InsightSummary item.
struct InsightSummaryDto {
  identifier : String
  sourceType : String
  summary : String
  sourceUrl : String
  collectedAt : String
  signalClass : String
  soWhatScore : Double
}

/// Parse an InsightSummaryDto from raw JSON.
fn parse_insight_summary_dto(
  json : @core.Any
) -> Result[InsightSummaryDto, AclError] {
  let identifier = match get_string(json, "identifier") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let source_type = match get_string(json, "sourceType") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let summary = match get_string(json, "summary") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let source_url = match get_string(json, "sourceUrl") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let collected_at = match get_string(json, "collectedAt") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let signal_class = match get_string(json, "signalClass") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let so_what_score = match get_double(json, "soWhatScore") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok({
    identifier,
    sourceType: source_type,
    summary,
    sourceUrl: source_url,
    collectedAt: collected_at,
    signalClass: signal_class,
    soWhatScore: so_what_score,
  })
}

/// Domain view model for a single insight item.
pub(all) struct InsightView {
  identifier : String
  sourceType : String
  summary : String
  sourceUrl : String
  collectedAt : String
  signalClass : String
  soWhatScore : Double
} derive(Show)

/// Output of insight list conversion.
pub(all) struct InsightListView {
  items : Array[InsightView]
  nextCursor : String?
} derive(Show)

/// Convert a BFF InsightListResponse JSON into an InsightListView.
pub fn convert_insight_list_response(
  json : @core.Any
) -> Result[InsightListView, AclError] {
  let items_raw = match get_array(json, "items") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let items : Array[InsightView] = []
  for item_json in items_raw {
    let dto = match parse_insight_summary_dto(item_json) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    items.push({
      identifier: dto.identifier,
      sourceType: dto.sourceType,
      summary: dto.summary,
      sourceUrl: dto.sourceUrl,
      collectedAt: dto.collectedAt,
      signalClass: dto.signalClass,
      soWhatScore: dto.soWhatScore,
    })
  }
  let next_cursor = get_string_opt(json, "nextCursor")
  Ok({ items, nextCursor: next_cursor })
}

/// Convert an InsightListView into ViewItems + Pagination for the domain projection.
pub fn insight_list_to_projection(
  view : InsightListView,
  limit : Int
) -> (Array[@projection.ViewItem], @projection.Pagination) {
  let view_items = view.items.map(fn(insight) {
    @projection.new_view_item(insight.identifier)
  })
  let pagination = @projection.new_pagination(
    view.nextCursor,
    limit,
    not(view.nextCursor.is_empty()),
  )
  (view_items, pagination)
}

// ============================================================================
// Hypotheses — /hypotheses (GET)
// Schema: HypothesisListResponse, HypothesisSummary → HypothesisListView
// ============================================================================

/// DTO for a HypothesisSummary item.
struct HypothesisSummaryDto {
  identifier : String
  symbol : String
  instrumentType : String
  status : String
  title : String
  updatedAt : String
}

/// Parse a HypothesisSummaryDto from raw JSON.
fn parse_hypothesis_summary_dto(
  json : @core.Any
) -> Result[HypothesisSummaryDto, AclError] {
  let identifier = match get_string(json, "identifier") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let symbol = match get_string(json, "symbol") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let instrument_type = match get_string(json, "instrumentType") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let status = match get_string(json, "status") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let title = match get_string(json, "title") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let updated_at = match get_string(json, "updatedAt") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok({
    identifier,
    symbol,
    instrumentType: instrument_type,
    status,
    title,
    updatedAt: updated_at,
  })
}

/// Domain view model for a single hypothesis item.
pub(all) struct HypothesisView {
  identifier : String
  symbol : String
  instrumentType : String
  status : String
  title : String
  updatedAt : String
} derive(Show)

/// Output of hypothesis list conversion.
pub(all) struct HypothesisListView {
  items : Array[HypothesisView]
  nextCursor : String?
} derive(Show)

/// Convert a BFF HypothesisListResponse JSON into a HypothesisListView.
pub fn convert_hypothesis_list_response(
  json : @core.Any
) -> Result[HypothesisListView, AclError] {
  let items_raw = match get_array(json, "items") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let items : Array[HypothesisView] = []
  for item_json in items_raw {
    let dto = match parse_hypothesis_summary_dto(item_json) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    items.push({
      identifier: dto.identifier,
      symbol: dto.symbol,
      instrumentType: dto.instrumentType,
      status: dto.status,
      title: dto.title,
      updatedAt: dto.updatedAt,
    })
  }
  let next_cursor = get_string_opt(json, "nextCursor")
  Ok({ items, nextCursor: next_cursor })
}

/// Convert a HypothesisListView into ViewItems + Pagination for the domain projection.
pub fn hypothesis_list_to_projection(
  view : HypothesisListView,
  limit : Int
) -> (Array[@projection.ViewItem], @projection.Pagination) {
  let view_items = view.items.map(fn(hypothesis) {
    @projection.new_view_item(hypothesis.identifier)
  })
  let pagination = @projection.new_pagination(
    view.nextCursor,
    limit,
    not(view.nextCursor.is_empty()),
  )
  (view_items, pagination)
}

// ============================================================================
// Model Validation — /models/validation (GET)
// Schema: ModelValidationListResponse, ModelValidationSummary → ModelValidationListView
// ============================================================================

/// DTO for a ModelValidationSummary item.
struct ModelValidationSummaryDto {
  modelVersion : String
  status : String
  degradationFlag : String
  createdAt : String
}

/// Parse a ModelValidationSummaryDto from raw JSON.
fn parse_model_validation_summary_dto(
  json : @core.Any
) -> Result[ModelValidationSummaryDto, AclError] {
  let model_version = match get_string(json, "modelVersion") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let status = match get_string(json, "status") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let degradation_flag = match get_string(json, "degradationFlag") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let created_at = match get_string(json, "createdAt") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok({
    modelVersion: model_version,
    status,
    degradationFlag: degradation_flag,
    createdAt: created_at,
  })
}

/// Domain view model for a single model validation entry.
pub(all) struct ModelValidationView {
  modelVersion : String
  status : String
  degradationFlag : String
  createdAt : String
} derive(Show)

/// Output of model validation list conversion.
pub(all) struct ModelValidationListView {
  items : Array[ModelValidationView]
} derive(Show)

/// Convert a BFF ModelValidationListResponse JSON into a ModelValidationListView.
pub fn convert_model_validation_list_response(
  json : @core.Any
) -> Result[ModelValidationListView, AclError] {
  let items_raw = match get_array(json, "items") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let items : Array[ModelValidationView] = []
  for item_json in items_raw {
    let dto = match parse_model_validation_summary_dto(item_json) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    items.push({
      modelVersion: dto.modelVersion,
      status: dto.status,
      degradationFlag: dto.degradationFlag,
      createdAt: dto.createdAt,
    })
  }
  Ok({ items })
}

/// Convert a ModelValidationListView into ViewItems for the domain projection.
/// Model validation does not paginate (no nextCursor per schema).
pub fn model_validation_list_to_projection(
  view : ModelValidationListView
) -> Array[@projection.ViewItem] {
  view.items.map(fn(model) { @projection.new_view_item(model.modelVersion) })
}

// ============================================================================
// CommandAccepted — response for POST mutating commands
// Schema: CommandAccepted
// ============================================================================

/// DTO for CommandAccepted response.
pub struct CommandAcceptedDto {
  accepted : Bool
  identifier : String
  trace : String
} derive(Show)

/// Parse a CommandAcceptedDto from raw JSON.
pub fn parse_command_accepted(
  json : @core.Any
) -> Result[CommandAcceptedDto, AclError] {
  let accepted = match get_bool(json, "accepted") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let identifier = match get_string(json, "identifier") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let trace = match get_string(json, "trace") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok({ accepted, identifier, trace })
}

// ============================================================================
// OperationResult — response for runtime/kill-switch operations
// Schema: OperationResult
// ============================================================================

/// DTO for OperationResult response.
pub struct OperationResultDto {
  success : Bool
  trace : String
  message : String?
} derive(Show)

/// Parse an OperationResultDto from raw JSON.
pub fn parse_operation_result(
  json : @core.Any
) -> Result[OperationResultDto, AclError] {
  let success = match get_bool(json, "success") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let trace = match get_string(json, "trace") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let message = get_string_opt(json, "message")
  Ok({ success, trace, message })
}

// ============================================================================
// StrategySettings — /settings/strategy (GET / PUT)
// Schema: StrategySettings
// ============================================================================

/// DTO for StrategySettings.
pub struct StrategySettingsDto {
  market : String
  rebalanceFrequency : String
  symbols : Array[String]
  dailyLossLimit : Double
  positionConcentrationLimit : Double
  dailyOrderLimit : Int
} derive(Show)

/// Parse a StrategySettingsDto from raw JSON.
pub fn parse_strategy_settings(
  json : @core.Any
) -> Result[StrategySettingsDto, AclError] {
  let market = match get_string(json, "market") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let rebalance_frequency = match get_string(json, "rebalanceFrequency") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let symbols_raw = match get_array(json, "symbols") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let symbols : Array[String] = symbols_raw.map(fn(s) {
    let str : String = s.cast()
    str
  })
  let daily_loss_limit = match get_double(json, "dailyLossLimit") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let position_concentration_limit = match get_double(
    json,
    "positionConcentrationLimit",
  ) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let daily_order_limit = match get_int(json, "dailyOrderLimit") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok({
    market,
    rebalanceFrequency: rebalance_frequency,
    symbols,
    dailyLossLimit: daily_loss_limit,
    positionConcentrationLimit: position_concentration_limit,
    dailyOrderLimit: daily_order_limit,
  })
}

// ============================================================================
// Request builders — domain input → BFF request JSON objects
// ============================================================================

/// Build the JSON body for POST /auth/login.
pub fn build_login_request(email : String, password : String) -> @core.Any {
  let obj = @core.new_object()
  obj._set("email", @core.any(email))
  obj._set("password", @core.any(password))
  obj
}

/// Build the JSON body for POST /orders/{identifier}/approve.
pub fn build_approve_order_request(
  submission_identifier : String,
  trace : String
) -> @core.Any {
  let obj = @core.new_object()
  obj._set("idempotencyKey", @core.any(submission_identifier))
  obj._set("trace", @core.any(trace))
  obj
}

/// Build the JSON body for POST /orders/{identifier}/reject.
pub fn build_reject_order_request(
  submission_identifier : String,
  trace : String,
  reason_code : @command.OperatorActionReasonCode
) -> @core.Any {
  let obj = @core.new_object()
  obj._set("idempotencyKey", @core.any(submission_identifier))
  obj._set("trace", @core.any(trace))
  obj._set("reasonCode", @core.any(operator_reason_code_to_string(reason_code)))
  obj
}

/// Build the JSON body for POST /orders/{identifier}/retry.
pub fn build_retry_order_request(
  submission_identifier : String,
  trace : String
) -> @core.Any {
  let obj = @core.new_object()
  obj._set("idempotencyKey", @core.any(submission_identifier))
  obj._set("trace", @core.any(trace))
  obj
}

/// Build the JSON body for POST /models/validation/{modelVersion}/approve.
pub fn build_approve_model_request(
  submission_identifier : String,
  trace : String
) -> @core.Any {
  let obj = @core.new_object()
  obj._set("idempotencyKey", @core.any(submission_identifier))
  obj._set("trace", @core.any(trace))
  obj
}

/// Build the JSON body for POST /models/validation/{modelVersion}/reject.
pub fn build_reject_model_request(
  submission_identifier : String,
  trace : String
) -> @core.Any {
  let obj = @core.new_object()
  obj._set("idempotencyKey", @core.any(submission_identifier))
  obj._set("trace", @core.any(trace))
  obj
}

/// Build the JSON body for POST /insights/{identifier}/hypothesize.
pub fn build_hypothesize_insight_request(
  submission_identifier : String,
  trace : String
) -> @core.Any {
  let obj = @core.new_object()
  obj._set("idempotencyKey", @core.any(submission_identifier))
  obj._set("trace", @core.any(trace))
  obj
}

/// Build the JSON body for POST /hypotheses/{identifier}/promote.
pub fn build_promote_hypothesis_request(
  submission_identifier : String,
  trace : String
) -> @core.Any {
  let obj = @core.new_object()
  obj._set("idempotencyKey", @core.any(submission_identifier))
  obj._set("trace", @core.any(trace))
  obj
}

/// Build the JSON body for POST /hypotheses/{identifier}/adopt.
pub fn build_adopt_hypothesis_request(
  submission_identifier : String,
  trace : String
) -> @core.Any {
  let obj = @core.new_object()
  obj._set("idempotencyKey", @core.any(submission_identifier))
  obj._set("trace", @core.any(trace))
  obj
}

/// Build the JSON body for POST /commands/run-cycle.
pub fn build_run_cycle_request(
  submission_identifier : String,
  trace : String
) -> @core.Any {
  let obj = @core.new_object()
  obj._set("idempotencyKey", @core.any(submission_identifier))
  obj._set("trace", @core.any(trace))
  obj
}

/// Build the JSON body for PUT /operations/runtime.
pub fn build_runtime_operation_request(action : String) -> @core.Any {
  let obj = @core.new_object()
  obj._set("action", @core.any(action))
  obj
}

/// Build the JSON body for PUT /operations/kill-switch.
pub fn build_kill_switch_request(enable : Bool) -> @core.Any {
  let obj = @core.new_object()
  obj._set("enable", @core.any(enable))
  obj
}

// ============================================================================
// Private helpers
// ============================================================================

/// Convert a domain OperatorActionReasonCode to its BFF string value.
fn operator_reason_code_to_string(
  code : @command.OperatorActionReasonCode
) -> String {
  match code {
    @command.OperatorActionReasonCode::RiskThresholdExceeded =>
      "RISK_THRESHOLD_EXCEEDED"
    @command.OperatorActionReasonCode::PolicyViolation => "POLICY_VIOLATION"
    @command.OperatorActionReasonCode::ManualOverride => "MANUAL_OVERRIDE"
    @command.OperatorActionReasonCode::Other => "OTHER"
  }
}
