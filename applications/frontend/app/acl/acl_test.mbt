///| Unit tests for the ACL layer.
///|
///| Tests validate that BFF JSON responses (mocked as @core.Any objects) are
///| correctly converted to domain models. No real HTTP calls are made.
///|
///| Coverage:
///|   - JSON helper utilities (get_string, get_string_opt, get_int, get_bool, etc.)
///|   - parse_problem_detail: RFC 9457 → AclError::ApiProblem
///|   - convert_login_response: LoginResponse → LoginAclOutput
///|   - convert_dashboard_summary: DashboardSummary → DashboardView
///|   - convert_order_list_response: OrderListResponse → OrderListView
///|   - convert_audit_list_response: AuditListResponse → AuditListView
///|   - convert_insight_list_response: InsightListResponse → InsightListView
///|   - convert_hypothesis_list_response: HypothesisListResponse → HypothesisListView
///|   - convert_model_validation_list_response: ModelValidationListResponse → ModelValidationListView
///|   - parse_command_accepted: CommandAccepted → CommandAcceptedDto
///|   - parse_operation_result: OperationResult → OperationResultDto
///|   - parse_strategy_settings: StrategySettings → StrategySettingsDto
///|   - parse_role: role string → domain Role
///|   - operator_reason_code / build_* request builders
///|   - list_to_projection helpers: ViewItem / Pagination construction

// ============================================================================
// Helpers — build @core.Any JSON objects for tests
// ============================================================================

/// Create an object with string field assignments.
fn make_obj(fields : Array[(String, @core.Any)]) -> @core.Any {
  let obj = @core.new_object()
  for pair in fields {
    obj._set(pair.0, pair.1)
  }
  obj
}

fn any_str(s : String) -> @core.Any {
  @core.any(s)
}

fn any_int(n : Int) -> @core.Any {
  @core.any(n)
}

fn any_double(d : Double) -> @core.Any {
  @core.any(d)
}

fn any_bool(b : Bool) -> @core.Any {
  @core.any(b)
}

fn any_array(items : Array[@core.Any]) -> @core.Any {
  @core.identity(items)
}

// ============================================================================
// JSON helper tests
// ============================================================================

test "get_string/returns_ok_for_existing_key" {
  let obj = make_obj([("name", any_str("alpha"))])
  match get_string(obj, "name") {
    Ok(s) => assert_eq!(s, "alpha")
    Err(_) => abort("Expected Ok")
  }
}

test "get_string/returns_missing_field_error_for_absent_key" {
  let obj = make_obj([])
  match get_string(obj, "missing") {
    Ok(_) => abort("Expected Err")
    Err(AclError::MissingField(msg)) => assert_true!(msg.contains("missing"))
    Err(_) => abort("Expected MissingField")
  }
}

test "get_string_opt/returns_none_for_absent_key" {
  let obj = make_obj([])
  assert_true!(get_string_opt(obj, "key").is_empty())
}

test "get_string_opt/returns_some_for_present_key" {
  let obj = make_obj([("key", any_str("val"))])
  match get_string_opt(obj, "key") {
    Some(s) => assert_eq!(s, "val")
    None => abort("Expected Some")
  }
}

test "get_int/returns_ok_for_existing_key" {
  let obj = make_obj([("count", any_int(42))])
  match get_int(obj, "count") {
    Ok(n) => assert_eq!(n, 42)
    Err(_) => abort("Expected Ok")
  }
}

test "get_int/returns_missing_field_error_for_absent_key" {
  let obj = make_obj([])
  match get_int(obj, "count") {
    Err(AclError::MissingField(_)) => ()
    _ => abort("Expected MissingField")
  }
}

test "get_double/returns_ok_for_existing_key" {
  let obj = make_obj([("ratio", any_double(3.14))])
  match get_double(obj, "ratio") {
    Ok(d) => assert_true!(d > 3.0 && d < 3.2)
    Err(_) => abort("Expected Ok")
  }
}

test "get_bool/returns_ok_for_existing_key" {
  let obj = make_obj([("flag", any_bool(true))])
  match get_bool(obj, "flag") {
    Ok(b) => assert_true!(b)
    Err(_) => abort("Expected Ok")
  }
}

test "get_array/returns_ok_for_existing_key" {
  let arr = any_array([any_str("a"), any_str("b")])
  let obj = make_obj([("items", arr)])
  match get_array(obj, "items") {
    Ok(items) => assert_eq!(items.length(), 2)
    Err(_) => abort("Expected Ok")
  }
}

test "get_array/returns_missing_field_error_for_absent_key" {
  let obj = make_obj([])
  match get_array(obj, "items") {
    Err(AclError::MissingField(_)) => ()
    _ => abort("Expected MissingField")
  }
}

// ============================================================================
// parse_problem_detail tests
// ============================================================================

test "parse_problem_detail/parses_standard_problem_json" {
  let json = make_obj([
    ("status", any_int(401)),
    ("title", any_str("Unauthorized")),
    ("detail", any_str("Token expired")),
    ("trace", any_str("01ARZ3NDEKTSV4RRFFQ69G5FAV")),
    ("reasonCode", any_str("AUTH_TOKEN_EXPIRED")),
    ("retryable", any_bool(false)),
  ])
  match parse_problem_detail(json) {
    AclError::ApiProblem(problem) => {
      assert_eq!(problem.status, 401)
      assert_eq!(problem.reasonCode, @command.ReasonCode::AuthUnauthorized)
      assert_eq!(problem.retryable, false)
    }
    _ => abort("Expected ApiProblem")
  }
}

test "parse_problem_detail/falls_back_to_internal_error_for_unknown_reason_code" {
  let json = make_obj([
    ("status", any_int(500)),
    ("title", any_str("Internal Server Error")),
    ("reasonCode", any_str("TOTALLY_UNKNOWN_CODE")),
  ])
  match parse_problem_detail(json) {
    AclError::ApiProblem(problem) =>
      assert_eq!(problem.reasonCode, @command.ReasonCode::InternalError)
    _ => abort("Expected ApiProblem")
  }
}

test "parse_problem_detail/uses_retryable_status_when_retryable_field_absent" {
  let json = make_obj([
    ("status", any_int(503)),
    ("title", any_str("Service Unavailable")),
    ("reasonCode", any_str("DEPENDENCY_UNAVAILABLE")),
  ])
  match parse_problem_detail(json) {
    AclError::ApiProblem(problem) => assert_true!(problem.retryable)
    _ => abort("Expected ApiProblem")
  }
}

// ============================================================================
// parse_role tests
// ============================================================================

test "parse_role/admin_maps_to_Admin" {
  assert_eq!(parse_role("admin"), @session.Role::Admin)
}

test "parse_role/viewer_maps_to_Viewer" {
  assert_eq!(parse_role("viewer"), @session.Role::Viewer)
}

test "parse_role/unknown_defaults_to_Viewer" {
  assert_eq!(parse_role("superuser"), @session.Role::Viewer)
}

// ============================================================================
// convert_login_response tests
// ============================================================================

fn make_login_response_json(role : String) -> @core.Any {
  let user = make_obj([
    ("identifier", any_str("user-001")),
    ("email", any_str("user@example.com")),
    ("role", any_str(role)),
    (
      "permissions",
      any_array([any_str("orders:approve"), any_str("orders:reject")]),
    ),
  ])
  make_obj([
    ("accessToken", any_str("eyJhbGciOiJSUzI1NiJ9.test")),
    ("tokenType", any_str("Bearer")),
    ("expiresIn", any_int(3600)),
    ("user", user),
  ])
}

test "convert_login_response/parses_admin_login_correctly" {
  let json = make_login_response_json("admin")
  match convert_login_response(json) {
    Ok(output) => {
      assert_eq!(output.subject, "user-001")
      assert_eq!(output.email, "user@example.com")
      assert_eq!(output.role, @session.Role::Admin)
      assert_eq!(output.permissions.length(), 2)
      assert_eq!(output.accessToken, "eyJhbGciOiJSUzI1NiJ9.test")
      assert_eq!(output.tokenType, "Bearer")
      assert_eq!(output.expiresIn, 3600)
    }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

test "convert_login_response/permissions_converted_to_domain_Permission" {
  let json = make_login_response_json("viewer")
  match convert_login_response(json) {
    Ok(output) => {
      assert_eq!(output.permissions[0].value, "orders:approve")
      assert_eq!(output.permissions[1].value, "orders:reject")
    }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

test "convert_login_response/returns_missing_field_error_when_access_token_absent" {
  let user = make_obj([
    ("identifier", any_str("user-001")),
    ("email", any_str("user@example.com")),
    ("role", any_str("admin")),
    ("permissions", any_array([])),
  ])
  let json = make_obj([
    ("tokenType", any_str("Bearer")),
    ("expiresIn", any_int(3600)),
    ("user", user),
  ])
  match convert_login_response(json) {
    Err(AclError::MissingField(_)) => ()
    _ => abort("Expected MissingField error")
  }
}

// ============================================================================
// convert_dashboard_summary tests
// ============================================================================

fn make_dashboard_summary_json() -> @core.Any {
  make_obj([
    ("pnlToday", any_double(1500.0)),
    ("pnlTotal", any_double(42000.0)),
    ("maxDrawdown", any_double(5.3)),
    ("runtimeState", any_str("RUNNING")),
    ("killSwitchEnabled", any_bool(false)),
    ("latestSignalAt", any_str("2026-01-15T09:00:00Z")),
  ])
}

test "convert_dashboard_summary/parses_correctly" {
  let json = make_dashboard_summary_json()
  match convert_dashboard_summary(json) {
    Ok(view) => {
      assert_eq!(view.runtimeState, "RUNNING")
      assert_eq!(view.killSwitchEnabled, false)
      assert_eq!(view.latestSignalAt, "2026-01-15T09:00:00Z")
    }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

test "convert_dashboard_summary/returns_error_when_required_field_missing" {
  let json = make_obj([("pnlToday", any_double(1500.0))])
  match convert_dashboard_summary(json) {
    Err(AclError::MissingField(_)) => ()
    _ => abort("Expected MissingField error")
  }
}

// ============================================================================
// convert_order_list_response tests
// ============================================================================

fn make_order_item_json(identifier : String, status : String) -> @core.Any {
  make_obj([
    ("identifier", any_str(identifier)),
    ("symbol", any_str("1306.T")),
    ("side", any_str("BUY")),
    ("qty", any_double(100.0)),
    ("status", any_str(status)),
    ("createdAt", any_str("2026-01-15T09:00:00Z")),
  ])
}

test "convert_order_list_response/parses_items_correctly" {
  let json = make_obj([
    (
      "items",
      any_array([
        make_order_item_json("order-001", "PROPOSED"),
        make_order_item_json("order-002", "APPROVED"),
      ]),
    ),
  ])
  match convert_order_list_response(json) {
    Ok(view) => {
      assert_eq!(view.items.length(), 2)
      assert_eq!(view.items[0].identifier, "order-001")
      assert_eq!(view.items[0].status, "PROPOSED")
      assert_eq!(view.items[1].identifier, "order-002")
      assert_eq!(view.items[1].status, "APPROVED")
      assert_true!(view.nextCursor.is_empty())
    }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

test "convert_order_list_response/captures_next_cursor" {
  let json = make_obj([
    ("items", any_array([make_order_item_json("order-001", "PROPOSED")])),
    ("nextCursor", any_str("cursor-abc")),
  ])
  match convert_order_list_response(json) {
    Ok(view) =>
      match view.nextCursor {
        Some(cursor) => assert_eq!(cursor, "cursor-abc")
        None => abort("Expected nextCursor")
      }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

test "convert_order_list_response/handles_empty_items_array" {
  let json = make_obj([("items", any_array([]))])
  match convert_order_list_response(json) {
    Ok(view) => assert_eq!(view.items.length(), 0)
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

// ============================================================================
// order_list_to_projection tests
// ============================================================================

test "order_list_to_projection/creates_view_items_and_pagination" {
  let view : OrderListView = {
    items: [
      {
        identifier: "ord-001",
        symbol: "1306.T",
        side: "BUY",
        qty: 10.0,
        status: "PROPOSED",
        createdAt: "2026-01-01T00:00:00Z",
      },
    ],
    nextCursor: Some("cursor-xyz"),
  }
  let (view_items, pagination) = order_list_to_projection(view, 20)
  assert_eq!(view_items.length(), 1)
  assert_eq!(view_items[0].identifier, "ord-001")
  assert_eq!(pagination.limit, 20)
  assert_true!(pagination.hasNext)
  match pagination.cursor {
    Some(c) => assert_eq!(c, "cursor-xyz")
    None => abort("Expected cursor")
  }
}

test "order_list_to_projection/has_next_false_when_no_cursor" {
  let view : OrderListView = { items: [], nextCursor: None }
  let (_, pagination) = order_list_to_projection(view, 20)
  assert_false!(pagination.hasNext)
}

// ============================================================================
// convert_audit_list_response tests
// ============================================================================

fn make_audit_item_json(identifier : String) -> @core.Any {
  make_obj([
    ("identifier", any_str(identifier)),
    ("occurredAt", any_str("2026-01-15T09:00:00Z")),
    ("eventType", any_str("order.approved")),
    ("service", any_str("svc-execution")),
    ("result", any_str("success")),
    ("trace", any_str("01ARZ3NDEKTSV4RRFFQ69G5FAV")),
  ])
}

test "convert_audit_list_response/parses_items_correctly" {
  let json = make_obj([
    (
      "items",
      any_array([make_audit_item_json("audit-001"), make_audit_item_json("audit-002")]),
    ),
  ])
  match convert_audit_list_response(json) {
    Ok(view) => {
      assert_eq!(view.items.length(), 2)
      assert_eq!(view.items[0].identifier, "audit-001")
      assert_eq!(view.items[0].eventType, "order.approved")
      assert_eq!(view.items[0].result, "success")
    }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

test "convert_audit_list_response/captures_next_cursor" {
  let json = make_obj([
    ("items", any_array([make_audit_item_json("audit-001")])),
    ("nextCursor", any_str("audit-cursor")),
  ])
  match convert_audit_list_response(json) {
    Ok(view) =>
      match view.nextCursor {
        Some(cursor) => assert_eq!(cursor, "audit-cursor")
        None => abort("Expected nextCursor")
      }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

// ============================================================================
// audit_list_to_projection tests
// ============================================================================

test "audit_list_to_projection/creates_view_items_and_pagination" {
  let view : AuditListView = {
    items: [
      {
        identifier: "aud-001",
        occurredAt: "2026-01-01T00:00:00Z",
        eventType: "order.approved",
        service: "svc-execution",
        result: "success",
        trace: "trace-001",
      },
    ],
    nextCursor: None,
  }
  let (view_items, pagination) = audit_list_to_projection(view, 50)
  assert_eq!(view_items.length(), 1)
  assert_eq!(view_items[0].identifier, "aud-001")
  assert_eq!(pagination.limit, 50)
  assert_false!(pagination.hasNext)
}

// ============================================================================
// convert_insight_list_response tests
// ============================================================================

fn make_insight_item_json(identifier : String) -> @core.Any {
  make_obj([
    ("identifier", any_str(identifier)),
    ("sourceType", any_str("x")),
    ("summary", any_str("High-volatility signal detected")),
    ("sourceUrl", any_str("https://x.com/post/123")),
    ("collectedAt", any_str("2026-01-15T09:00:00Z")),
    ("signalClass", any_str("structural_anomaly")),
    ("soWhatScore", any_double(0.82)),
  ])
}

test "convert_insight_list_response/parses_items_correctly" {
  let json = make_obj([
    (
      "items",
      any_array([
        make_insight_item_json("insight-001"),
        make_insight_item_json("insight-002"),
      ]),
    ),
  ])
  match convert_insight_list_response(json) {
    Ok(view) => {
      assert_eq!(view.items.length(), 2)
      assert_eq!(view.items[0].identifier, "insight-001")
      assert_eq!(view.items[0].sourceType, "x")
      assert_eq!(view.items[0].signalClass, "structural_anomaly")
    }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

test "convert_insight_list_response/handles_no_next_cursor" {
  let json = make_obj([("items", any_array([make_insight_item_json("insight-001")]))])
  match convert_insight_list_response(json) {
    Ok(view) => assert_true!(view.nextCursor.is_empty())
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

// ============================================================================
// convert_hypothesis_list_response tests
// ============================================================================

fn make_hypothesis_item_json(identifier : String) -> @core.Any {
  make_obj([
    ("identifier", any_str(identifier)),
    ("symbol", any_str("1306.T")),
    ("instrumentType", any_str("ETF")),
    ("status", any_str("draft")),
    ("title", any_str("低ボラETFの押し目反発仮説")),
    ("updatedAt", any_str("2026-01-15T09:00:00Z")),
  ])
}

test "convert_hypothesis_list_response/parses_items_correctly" {
  let json = make_obj([
    (
      "items",
      any_array([
        make_hypothesis_item_json("hyp-001"),
        make_hypothesis_item_json("hyp-002"),
      ]),
    ),
  ])
  match convert_hypothesis_list_response(json) {
    Ok(view) => {
      assert_eq!(view.items.length(), 2)
      assert_eq!(view.items[0].identifier, "hyp-001")
      assert_eq!(view.items[0].instrumentType, "ETF")
      assert_eq!(view.items[0].status, "draft")
    }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

test "convert_hypothesis_list_response/handles_empty_items" {
  let json = make_obj([("items", any_array([]))])
  match convert_hypothesis_list_response(json) {
    Ok(view) => assert_eq!(view.items.length(), 0)
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

// ============================================================================
// convert_model_validation_list_response tests
// ============================================================================

fn make_model_item_json(model_version : String, status : String) -> @core.Any {
  make_obj([
    ("modelVersion", any_str(model_version)),
    ("status", any_str(status)),
    ("degradationFlag", any_str("normal")),
    ("createdAt", any_str("2026-01-15T09:00:00Z")),
  ])
}

test "convert_model_validation_list_response/parses_items_correctly" {
  let json = make_obj([
    (
      "items",
      any_array([
        make_model_item_json("v1.2.0", "candidate"),
        make_model_item_json("v1.1.0", "approved"),
      ]),
    ),
  ])
  match convert_model_validation_list_response(json) {
    Ok(view) => {
      assert_eq!(view.items.length(), 2)
      assert_eq!(view.items[0].modelVersion, "v1.2.0")
      assert_eq!(view.items[0].status, "candidate")
      assert_eq!(view.items[0].degradationFlag, "normal")
      assert_eq!(view.items[1].status, "approved")
    }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

test "model_validation_list_to_projection/creates_view_items_keyed_by_model_version" {
  let view : ModelValidationListView = {
    items: [
      {
        modelVersion: "v1.2.0",
        status: "candidate",
        degradationFlag: "normal",
        createdAt: "2026-01-01T00:00:00Z",
      },
    ],
  }
  let view_items = model_validation_list_to_projection(view)
  assert_eq!(view_items.length(), 1)
  assert_eq!(view_items[0].identifier, "v1.2.0")
}

// ============================================================================
// parse_command_accepted tests
// ============================================================================

test "parse_command_accepted/parses_correctly" {
  let json = make_obj([
    ("accepted", any_bool(true)),
    ("identifier", any_str("01ARZ3NDEKTSV4RRFFQ69G5FAV")),
    ("trace", any_str("01ARZ3NDEKTSV4RRFFQ69G5FAV")),
  ])
  match parse_command_accepted(json) {
    Ok(dto) => {
      assert_true!(dto.accepted)
      assert_eq!(dto.identifier, "01ARZ3NDEKTSV4RRFFQ69G5FAV")
    }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

test "parse_command_accepted/returns_error_when_accepted_missing" {
  let json = make_obj([
    ("identifier", any_str("01ARZ3NDEKTSV4RRFFQ69G5FAV")),
    ("trace", any_str("01ARZ3NDEKTSV4RRFFQ69G5FAV")),
  ])
  match parse_command_accepted(json) {
    Err(AclError::MissingField(_)) => ()
    _ => abort("Expected MissingField")
  }
}

// ============================================================================
// parse_operation_result tests
// ============================================================================

test "parse_operation_result/parses_success_result" {
  let json = make_obj([
    ("success", any_bool(true)),
    ("trace", any_str("trace-001")),
    ("message", any_str("Runtime started")),
  ])
  match parse_operation_result(json) {
    Ok(dto) => {
      assert_true!(dto.success)
      assert_eq!(dto.trace, "trace-001")
      match dto.message {
        Some(msg) => assert_eq!(msg, "Runtime started")
        None => abort("Expected message")
      }
    }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

test "parse_operation_result/message_is_optional" {
  let json = make_obj([("success", any_bool(false)), ("trace", any_str("trace-002"))])
  match parse_operation_result(json) {
    Ok(dto) => {
      assert_false!(dto.success)
      assert_true!(dto.message.is_empty())
    }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

// ============================================================================
// parse_strategy_settings tests
// ============================================================================

test "parse_strategy_settings/parses_correctly" {
  let json = make_obj([
    ("market", any_str("JP")),
    ("rebalanceFrequency", any_str("daily")),
    (
      "symbols",
      any_array([any_str("1306.T"), any_str("1321.T"), any_str("1348.T")]),
    ),
    ("dailyLossLimit", any_double(2.0)),
    ("positionConcentrationLimit", any_double(20.0)),
    ("dailyOrderLimit", any_int(10)),
  ])
  match parse_strategy_settings(json) {
    Ok(dto) => {
      assert_eq!(dto.market, "JP")
      assert_eq!(dto.rebalanceFrequency, "daily")
      assert_eq!(dto.symbols.length(), 3)
      assert_eq!(dto.symbols[0], "1306.T")
      assert_eq!(dto.dailyOrderLimit, 10)
    }
    Err(e) => abort("Expected Ok: " + e.to_string())
  }
}

// ============================================================================
// BffClient tests
// ============================================================================

test "BffClient/new_creates_client_with_correct_fields" {
  let client = BffClient::new("https://api.alpha-mind.dev", "token-abc")
  assert_eq!(client.baseUrl, "https://api.alpha-mind.dev")
  assert_eq!(client.accessToken, "token-abc")
}

test "BffClient/authorization_header_returns_bearer_token" {
  let client = BffClient::new("https://api.alpha-mind.dev", "my-jwt")
  assert_eq!(client.authorization_header(), "Bearer my-jwt")
}

// ============================================================================
// Request builder tests
// ============================================================================

test "build_login_request/sets_email_and_password" {
  let req = build_login_request("user@example.com", "P@ssw0rd123!")
  let email : String = req._get("email").cast()
  let password : String = req._get("password").cast()
  assert_eq!(email, "user@example.com")
  assert_eq!(password, "P@ssw0rd123!")
}

test "build_approve_order_request/sets_idempotency_key_and_trace" {
  let req = build_approve_order_request("sub-001", "trace-001")
  let key : String = req._get("idempotencyKey").cast()
  let trace : String = req._get("trace").cast()
  assert_eq!(key, "sub-001")
  assert_eq!(trace, "trace-001")
}

test "build_reject_order_request/sets_reason_code" {
  let req = build_reject_order_request(
    "sub-002",
    "trace-002",
    @command.OperatorActionReasonCode::RiskThresholdExceeded,
  )
  let reason_code : String = req._get("reasonCode").cast()
  assert_eq!(reason_code, "RISK_THRESHOLD_EXCEEDED")
}

test "build_reject_order_request/manual_override_reason_code" {
  let req = build_reject_order_request(
    "sub-003",
    "trace-003",
    @command.OperatorActionReasonCode::ManualOverride,
  )
  let reason_code : String = req._get("reasonCode").cast()
  assert_eq!(reason_code, "MANUAL_OVERRIDE")
}

test "build_run_cycle_request/sets_required_fields" {
  let req = build_run_cycle_request("sub-010", "trace-010")
  let key : String = req._get("idempotencyKey").cast()
  assert_eq!(key, "sub-010")
}

test "build_runtime_operation_request/sets_action" {
  let req = build_runtime_operation_request("START")
  let action : String = req._get("action").cast()
  assert_eq!(action, "START")
}

test "build_kill_switch_request/enable_true" {
  let req = build_kill_switch_request(true)
  let enable : Bool = req._get("enable").cast()
  assert_true!(enable)
}

test "build_kill_switch_request/enable_false" {
  let req = build_kill_switch_request(false)
  let enable : Bool = req._get("enable").cast()
  assert_false!(enable)
}

// ============================================================================
// insight_list_to_projection tests
// ============================================================================

test "insight_list_to_projection/creates_view_items_and_pagination" {
  let view : InsightListView = {
    items: [
      {
        identifier: "ins-001",
        sourceType: "x",
        summary: "Test",
        sourceUrl: "https://x.com/post/1",
        collectedAt: "2026-01-01T00:00:00Z",
        signalClass: "structural_anomaly",
        soWhatScore: 0.9,
      },
    ],
    nextCursor: Some("ins-cursor"),
  }
  let (view_items, pagination) = insight_list_to_projection(view, 30)
  assert_eq!(view_items.length(), 1)
  assert_eq!(view_items[0].identifier, "ins-001")
  assert_true!(pagination.hasNext)
  assert_eq!(pagination.limit, 30)
}

// ============================================================================
// hypothesis_list_to_projection tests
// ============================================================================

test "hypothesis_list_to_projection/creates_view_items_and_pagination" {
  let view : HypothesisListView = {
    items: [
      {
        identifier: "hyp-001",
        symbol: "1306.T",
        instrumentType: "ETF",
        status: "draft",
        title: "Test Hypothesis",
        updatedAt: "2026-01-01T00:00:00Z",
      },
    ],
    nextCursor: None,
  }
  let (view_items, pagination) = hypothesis_list_to_projection(view, 20)
  assert_eq!(view_items.length(), 1)
  assert_eq!(view_items[0].identifier, "hyp-001")
  assert_false!(pagination.hasNext)
}
