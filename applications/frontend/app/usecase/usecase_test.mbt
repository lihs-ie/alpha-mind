///| Unit tests for the usecase layer.
///|
///| Uses in-memory stub implementations of repository ports to test each
///| application service in isolation from HTTP / IO. Stubs are local to this
///| test module and are NOT compiled into the production package.

// ============================================================================
// In-memory stub implementations (test-only)
// ============================================================================

/// Minimal in-memory session repository stub for tests.
struct InMemorySessionRepository {
  mut session : @session.UiSession?
}

impl @policy.UiSessionRepository for InMemorySessionRepository with find(
  self,
  _identifier
) {
  self.session
}

impl @policy.UiSessionRepository for InMemorySessionRepository with persist(
  self,
  s
) {
  self.session = Some(s)
}

impl @policy.UiSessionRepository for InMemorySessionRepository with terminate(
  self,
  _identifier
) {
  self.session = None
}

/// Minimal in-memory projection repository stub for tests.
struct InMemoryProjectionRepository {
  mut projection : @projection.ReadModelProjection?
}

impl @policy.ProjectionRepository for InMemoryProjectionRepository with find_by_screen(
  self,
  _screen
) {
  self.projection
}

impl @policy.ProjectionRepository for InMemoryProjectionRepository with persist(
  self,
  p
) {
  self.projection = Some(p)
}

impl @policy.ProjectionRepository for InMemoryProjectionRepository with terminate(
  self,
  _identifier
) {
  self.projection = None
}

// ============================================================================
// Helpers
// ============================================================================

fn make_authenticated_session(identifier : String) -> @session.UiSession {
  let session = @session.new_session(identifier, "2026-01-01T00:00:00Z")
  let permission_snapshot : @session.PermissionSnapshot = {
    role: @session.Role::Admin,
    permissions: [],
  }
  match @session.authenticate(session, "user-001", permission_snapshot, "2026-01-01T00:00:01Z") {
    Ok(s) => s
    Err(_) => abort("helper: authenticate failed unexpectedly")
  }
}

fn make_session_repo_with_authenticated() -> InMemorySessionRepository {
  let repo : InMemorySessionRepository = { session: None }
  let s = make_authenticated_session("sess-001")
  repo.persist(s)
  repo
}

// ============================================================================
// AuthenticationService tests
// ============================================================================

test "login/creates_session_when_none_exists" {
  let repo : InMemorySessionRepository = { session: None }
  let input : LoginInput = {
    user: "user-001",
    role: @session.Role::Admin,
    permissions: [],
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = login(repo, "sess-new", input)
  assert_true!(result.is_ok())
  match result {
    Ok(output) => assert_eq!(output.session.authState, @session.AuthState::Authenticated)
    Err(_) => abort("Expected Ok")
  }
}

test "login/returns_domain_violation_when_already_authenticated" {
  let repo = make_session_repo_with_authenticated()
  let input : LoginInput = {
    user: "user-002",
    role: @session.Role::Viewer,
    permissions: [],
    updatedAt: "2026-01-01T00:00:02Z",
  }
  let result = login(repo, "sess-001", input)
  assert_true!(result.is_err())
  match result {
    Err(UsecaseError::DomainViolation(_)) => ()
    _ => abort("Expected DomainViolation")
  }
}

test "logout/expires_authenticated_session" {
  let repo = make_session_repo_with_authenticated()
  let result = logout(repo, "sess-001", "2026-01-01T00:01:00Z")
  assert_true!(result.is_ok())
}

test "logout/returns_unauthorized_when_session_not_found" {
  let repo : InMemorySessionRepository = { session: None }
  let result = logout(repo, "no-such-session", "2026-01-01T00:00:00Z")
  assert_true!(result.is_err())
  match result {
    Err(UsecaseError::Unauthorized(_)) => ()
    _ => abort("Expected Unauthorized")
  }
}

test "navigate/authenticated_to_protected_screen_ok" {
  let repo = make_session_repo_with_authenticated()
  let result = navigate(repo, "sess-001", @session.Screen::Scr001, "2026-01-01T00:00:02Z")
  assert_true!(result.is_ok())
  match result {
    Ok(s) => assert_eq!(s.currentScreen, @session.Screen::Scr001)
    Err(_) => abort("Expected Ok")
  }
}

test "navigate/unauthenticated_to_protected_screen_returns_error" {
  let repo : InMemorySessionRepository = { session: None }
  let s = @session.new_session("sess-unauth", "2026-01-01T00:00:00Z")
  repo.persist(s)
  let result = navigate(repo, "sess-unauth", @session.Screen::Scr001, "2026-01-01T00:00:01Z")
  assert_true!(result.is_err())
}

// ============================================================================
// DashboardQueryService tests
// ============================================================================

test "load_dashboard/creates_projection_in_loading_state" {
  let repo : InMemoryProjectionRepository = { projection: None }
  let input : LoadDashboardInput = {
    screen: @projection.ProjectionScreen::Scr001,
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = load_dashboard(repo, input)
  assert_eq!(result.status, @projection.ProjectionStatus::Loading)
}

test "refresh_dashboard/transitions_to_ready_when_items_present" {
  let repo : InMemoryProjectionRepository = { projection: None }
  let items = [@projection.new_view_item("item-001")]
  let result = refresh_dashboard(
    repo,
    @projection.ProjectionScreen::Scr001,
    items,
    None,
    None,
    "2026-01-01T00:00:01Z",
  )
  assert_eq!(result.status, @projection.ProjectionStatus::Ready)
  assert_eq!(result.items.length(), 1)
}

test "refresh_dashboard/transitions_to_empty_when_no_items_and_no_summary" {
  let repo : InMemoryProjectionRepository = { projection: None }
  let result = refresh_dashboard(
    repo,
    @projection.ProjectionScreen::Scr001,
    [],
    None,
    None,
    "2026-01-01T00:00:01Z",
  )
  assert_eq!(result.status, @projection.ProjectionStatus::Empty)
}

test "fail_dashboard/transitions_to_error_state" {
  let repo : InMemoryProjectionRepository = { projection: None }
  let result = fail_dashboard(
    repo,
    @projection.ProjectionScreen::Scr001,
    "2026-01-01T00:00:01Z",
  )
  assert_eq!(result.status, @projection.ProjectionStatus::Error)
}

// ============================================================================
// OrdersCommandService tests — RULE-FE-001, RULE-FE-003, RULE-FE-005
// ============================================================================

test "approve_order/authenticated_admin_returns_submitting_interaction" {
  let repo = make_session_repo_with_authenticated()
  let input : ApproveOrderInput = {
    sessionIdentifier: "sess-001",
    submissionIdentifier: "sub-001",
    trace: "trace-001",
    orderIdentifier: "order-001",
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = approve_order(repo, input, [])
  assert_true!(result.is_ok())
  match result {
    Ok(interaction) =>
      assert_eq!(interaction.status, @command.CommandStatus::Submitting)
    Err(_) => abort("Expected Ok")
  }
}

test "approve_order/returns_unauthorized_when_session_not_found" {
  let repo : InMemorySessionRepository = { session: None }
  let input : ApproveOrderInput = {
    sessionIdentifier: "no-session",
    submissionIdentifier: "sub-001",
    trace: "trace-001",
    orderIdentifier: "order-001",
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = approve_order(repo, input, [])
  assert_true!(result.is_err())
  match result {
    Err(UsecaseError::Unauthorized(_)) => ()
    _ => abort("Expected Unauthorized")
  }
}

test "approve_order/kill_switch_blocks_approve" {
  let repo : InMemorySessionRepository = { session: None }
  let base_session = make_authenticated_session("sess-ks")
  let kill_switch_session = {
    ..base_session,
    operationGuardState: {
      killSwitch: @session.KillSwitchState::Enabled,
      disabledActions: [],
    },
  }
  repo.persist(kill_switch_session)
  let input : ApproveOrderInput = {
    sessionIdentifier: "sess-ks",
    submissionIdentifier: "sub-ks",
    trace: "trace-ks",
    orderIdentifier: "order-ks",
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = approve_order(repo, input, [])
  assert_true!(result.is_err())
  match result {
    Err(UsecaseError::OperationBlocked(_)) => ()
    _ => abort("Expected OperationBlocked (TST-FE-003)")
  }
}

test "approve_order/duplicate_submission_returns_dedup_error" {
  let repo = make_session_repo_with_authenticated()
  let in_flight_interaction : @command.CommandInteraction = {
    identifier: "sub-dup",
    submissionIdentifier: "sub-dup",
    trace: "trace-dup",
    commandType: @session.CommandType::Approve,
    target: Some({ targetIdentifier: "order-dup", targetType: "order" }),
    status: @command.CommandStatus::Submitting,
    responseCode: None,
    reasonCode: None,
    actionReasonCode: None,
  }
  let input : ApproveOrderInput = {
    sessionIdentifier: "sess-001",
    submissionIdentifier: "sub-dup",
    trace: "trace-dup",
    orderIdentifier: "order-dup",
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = approve_order(repo, input, [in_flight_interaction])
  assert_true!(result.is_err())
  match result {
    Err(UsecaseError::DuplicateSubmission(_)) => ()
    _ => abort("Expected DuplicateSubmission (TST-FE-005)")
  }
}

test "reject_order/authenticated_admin_returns_submitting_interaction" {
  let repo = make_session_repo_with_authenticated()
  let input : RejectOrderInput = {
    sessionIdentifier: "sess-001",
    submissionIdentifier: "sub-002",
    trace: "trace-002",
    orderIdentifier: "order-002",
    actionReasonCode: @command.OperatorActionReasonCode::ManualOverride,
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = reject_order(repo, input, [])
  assert_true!(result.is_ok())
  match result {
    Ok(interaction) =>
      assert_eq!(interaction.status, @command.CommandStatus::Submitting)
    Err(_) => abort("Expected Ok")
  }
}

test "retry_order/authenticated_returns_submitting_interaction" {
  let repo = make_session_repo_with_authenticated()
  let input : RetryOrderInput = {
    sessionIdentifier: "sess-001",
    submissionIdentifier: "sub-003",
    trace: "trace-003",
    orderIdentifier: "order-003",
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = retry_order(repo, input, [])
  assert_true!(result.is_ok())
}

// ============================================================================
// ModelValidationService tests
// ============================================================================

test "approve_model/authenticated_returns_submitting_interaction" {
  let repo = make_session_repo_with_authenticated()
  let input : ApproveModelInput = {
    sessionIdentifier: "sess-001",
    submissionIdentifier: "sub-m001",
    trace: "trace-m001",
    modelVersion: "v1.0.0",
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = approve_model(repo, input, [])
  assert_true!(result.is_ok())
  match result {
    Ok(interaction) => {
      assert_eq!(interaction.status, @command.CommandStatus::Submitting)
      assert_eq!(interaction.commandType, @session.CommandType::Promote)
    }
    Err(_) => abort("Expected Ok")
  }
}

test "reject_model/authenticated_returns_submitting_interaction" {
  let repo = make_session_repo_with_authenticated()
  let input : RejectModelInput = {
    sessionIdentifier: "sess-001",
    submissionIdentifier: "sub-m002",
    trace: "trace-m002",
    modelVersion: "v1.0.0",
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = reject_model(repo, input, [])
  assert_true!(result.is_ok())
  match result {
    Ok(interaction) =>
      assert_eq!(interaction.commandType, @session.CommandType::Reject)
    Err(_) => abort("Expected Ok")
  }
}

// ============================================================================
// InsightQueryService tests
// ============================================================================

test "load_insights/creates_projection_in_loading_state" {
  let repo : InMemoryProjectionRepository = { projection: None }
  let input : LoadInsightsInput = {
    screen: @projection.ProjectionScreen::Scr006,
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = load_insights(repo, input)
  assert_eq!(result.status, @projection.ProjectionStatus::Loading)
}

test "hypothesize_insight/authenticated_returns_submitting_interaction" {
  let repo = make_session_repo_with_authenticated()
  let input : HypothesizeInsightInput = {
    sessionIdentifier: "sess-001",
    submissionIdentifier: "sub-i001",
    trace: "trace-i001",
    insightIdentifier: "insight-001",
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = hypothesize_insight(repo, input, [])
  assert_true!(result.is_ok())
  match result {
    Ok(interaction) =>
      assert_eq!(interaction.commandType, @session.CommandType::Hypothesize)
    Err(_) => abort("Expected Ok")
  }
}

// ============================================================================
// HypothesisWorkflowService tests
// ============================================================================

test "promote_hypothesis/authenticated_returns_submitting_interaction" {
  let repo = make_session_repo_with_authenticated()
  let input : PromoteHypothesisInput = {
    sessionIdentifier: "sess-001",
    submissionIdentifier: "sub-h001",
    trace: "trace-h001",
    hypothesisIdentifier: "hyp-001",
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = promote_hypothesis(repo, input, [])
  assert_true!(result.is_ok())
  match result {
    Ok(interaction) =>
      assert_eq!(interaction.commandType, @session.CommandType::Promote)
    Err(_) => abort("Expected Ok")
  }
}

test "adopt_hypothesis/authenticated_returns_submitting_interaction" {
  let repo = make_session_repo_with_authenticated()
  let input : AdoptHypothesisInput = {
    sessionIdentifier: "sess-001",
    submissionIdentifier: "sub-h002",
    trace: "trace-h002",
    hypothesisIdentifier: "hyp-002",
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = adopt_hypothesis(repo, input, [])
  assert_true!(result.is_ok())
  match result {
    Ok(interaction) =>
      assert_eq!(interaction.commandType, @session.CommandType::Adopt)
    Err(_) => abort("Expected Ok")
  }
}

// ============================================================================
// DashboardCommandService tests
// ============================================================================

test "run_cycle/authenticated_returns_submitting_interaction" {
  let repo = make_session_repo_with_authenticated()
  let input : RunCycleInput = {
    sessionIdentifier: "sess-001",
    submissionIdentifier: "sub-rc001",
    trace: "trace-rc001",
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = run_cycle(repo, input, [])
  assert_true!(result.is_ok())
  match result {
    Ok(interaction) =>
      assert_eq!(interaction.commandType, @session.CommandType::RunCycle)
    Err(_) => abort("Expected Ok")
  }
}

// ============================================================================
// CommandResponseService tests
// ============================================================================

test "acknowledge_command/transitions_submitting_to_accepted" {
  let interaction : @command.CommandInteraction = {
    identifier: "sub-ack",
    submissionIdentifier: "sub-ack",
    trace: "trace-ack",
    commandType: @session.CommandType::Approve,
    target: Some({ targetIdentifier: "order-ack", targetType: "order" }),
    status: @command.CommandStatus::Submitting,
    responseCode: None,
    reasonCode: None,
    actionReasonCode: None,
  }
  let result = acknowledge_command(interaction, 200)
  assert_true!(result.is_ok())
  match result {
    Ok(completed) => {
      assert_eq!(completed.status, @command.CommandStatus::Accepted)
      assert_eq!(completed.responseCode, Some(200))
    }
    Err(_) => abort("Expected Ok")
  }
}

test "reject_submitted_command/transitions_submitting_to_rejected" {
  let interaction : @command.CommandInteraction = {
    identifier: "sub-rej",
    submissionIdentifier: "sub-rej",
    trace: "trace-rej",
    commandType: @session.CommandType::Approve,
    target: Some({ targetIdentifier: "order-rej", targetType: "order" }),
    status: @command.CommandStatus::Submitting,
    responseCode: None,
    reasonCode: None,
    actionReasonCode: None,
  }
  let result = reject_submitted_command(
    interaction,
    403,
    @command.ReasonCode::KillSwitchEnabled,
  )
  assert_true!(result.is_ok())
  match result {
    Ok(completed) => {
      assert_eq!(completed.status, @command.CommandStatus::Rejected)
      assert_eq!(completed.reasonCode, Some(@command.ReasonCode::KillSwitchEnabled))
    }
    Err(_) => abort("Expected Ok")
  }
}

// ============================================================================
// AuditQueryService tests
// ============================================================================

test "load_audit_logs/creates_projection_in_loading_state" {
  let repo : InMemoryProjectionRepository = { projection: None }
  let input : QueryAuditLogsInput = {
    screen: @projection.ProjectionScreen::Scr004,
    criteria: @projection.new_query_criteria(None, None, None, None, Some(20)),
    updatedAt: "2026-01-01T00:00:00Z",
  }
  let result = load_audit_logs(repo, input)
  assert_eq!(result.status, @projection.ProjectionStatus::Loading)
}
