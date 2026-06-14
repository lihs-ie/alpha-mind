///| Unit tests for the infrastructure layer.
///|
///| Tests cover:
///|   - InMemorySessionRepository: find / persist / terminate
///|   - InMemoryProjectionRepository: find_by_screen / persist / terminate
///|   - JwtTokenStore: store / clear / status / access_token
///|   - ProblemDetail: parse_reason_code / new_problem_detail / is_retryable_status

// ============================================================================
// Helpers
// ============================================================================

fn make_session(identifier : String) -> @session.UiSession {
  @session.new_session(identifier, "2026-01-01T00:00:00Z")
}

fn make_authenticated_session(identifier : String) -> @session.UiSession {
  let s = @session.new_session(identifier, "2026-01-01T00:00:00Z")
  let snapshot : @session.PermissionSnapshot = {
    role: @session.Role::Admin,
    permissions: [],
  }
  match @session.authenticate(s, "user-001", snapshot, "2026-01-01T00:00:01Z") {
    Ok(authenticated_session) => authenticated_session
    Err(_) => abort("helper: authenticate should not fail")
  }
}

fn make_projection(
  identifier : String,
  screen : @projection.ProjectionScreen
) -> @projection.ReadModelProjection {
  @projection.new_projection(identifier, screen, "2026-01-01T00:00:00Z")
}

// ============================================================================
// InMemorySessionRepository tests
// ============================================================================

test "InMemorySessionRepository/find_returns_none_when_empty" {
  let repository = InMemorySessionRepository::new()
  let result = repository.find("sess-999")
  assert_true!(result.is_empty())
}

test "InMemorySessionRepository/persist_and_find_roundtrip" {
  let repository = InMemorySessionRepository::new()
  let session = make_session("sess-001")
  repository.persist(session)
  let result = repository.find("sess-001")
  assert_true!(not(result.is_empty()))
  match result {
    Some(stored_session) =>
      assert_eq!(stored_session.identifier, "sess-001")
    None => abort("Expected Some after persist")
  }
}

test "InMemorySessionRepository/persist_overwrites_existing_entry" {
  let repository = InMemorySessionRepository::new()
  let session = make_session("sess-001")
  repository.persist(session)
  let authenticated_session = make_authenticated_session("sess-001")
  repository.persist(authenticated_session)
  match repository.find("sess-001") {
    Some(stored_session) =>
      assert_eq!(stored_session.authState, @session.AuthState::Authenticated)
    None => abort("Expected Some after second persist")
  }
}

test "InMemorySessionRepository/terminate_removes_entry" {
  let repository = InMemorySessionRepository::new()
  let session = make_session("sess-001")
  repository.persist(session)
  repository.terminate("sess-001")
  assert_true!(repository.find("sess-001").is_empty())
}

test "InMemorySessionRepository/terminate_does_not_affect_other_entries" {
  let repository = InMemorySessionRepository::new()
  let session_a = make_session("sess-a")
  let session_b = make_session("sess-b")
  repository.persist(session_a)
  repository.persist(session_b)
  repository.terminate("sess-a")
  assert_true!(repository.find("sess-a").is_empty())
  assert_true!(not(repository.find("sess-b").is_empty()))
}

test "InMemorySessionRepository/persist_multiple_sessions" {
  let repository = InMemorySessionRepository::new()
  let session_a = make_session("sess-a")
  let session_b = make_session("sess-b")
  repository.persist(session_a)
  repository.persist(session_b)
  match (repository.find("sess-a"), repository.find("sess-b")) {
    (Some(sa), Some(sb)) => {
      assert_eq!(sa.identifier, "sess-a")
      assert_eq!(sb.identifier, "sess-b")
    }
    _ => abort("Expected both sessions to be found")
  }
}

test "InMemorySessionRepository/find_returns_none_for_unknown_identifier" {
  let repository = InMemorySessionRepository::new()
  let session = make_session("sess-known")
  repository.persist(session)
  assert_true!(repository.find("sess-unknown").is_empty())
}

// ============================================================================
// InMemoryProjectionRepository tests
// ============================================================================

test "InMemoryProjectionRepository/find_by_screen_returns_none_when_empty" {
  let repository = InMemoryProjectionRepository::new()
  let result = repository.find_by_screen(@projection.ProjectionScreen::Scr001)
  assert_true!(result.is_empty())
}

test "InMemoryProjectionRepository/persist_and_find_by_screen_roundtrip" {
  let repository = InMemoryProjectionRepository::new()
  let proj = make_projection("proj-001", @projection.ProjectionScreen::Scr001)
  repository.persist(proj)
  match repository.find_by_screen(@projection.ProjectionScreen::Scr001) {
    Some(stored_projection) =>
      assert_eq!(stored_projection.identifier, "proj-001")
    None => abort("Expected Some after persist")
  }
}

test "InMemoryProjectionRepository/persist_overwrites_existing_screen_entry" {
  let repository = InMemoryProjectionRepository::new()
  let proj_initial = make_projection(
    "proj-001",
    @projection.ProjectionScreen::Scr001,
  )
  repository.persist(proj_initial)
  let proj_loading = @projection.start_loading(proj_initial, "2026-01-01T00:01:00Z")
  repository.persist(proj_loading)
  match repository.find_by_screen(@projection.ProjectionScreen::Scr001) {
    Some(stored_projection) =>
      assert_eq!(stored_projection.status, @projection.ProjectionStatus::Loading)
    None => abort("Expected Some after second persist")
  }
}

test "InMemoryProjectionRepository/terminate_removes_entry_by_identifier" {
  let repository = InMemoryProjectionRepository::new()
  let proj = make_projection("proj-001", @projection.ProjectionScreen::Scr001)
  repository.persist(proj)
  repository.terminate("proj-001")
  assert_true!(
    repository.find_by_screen(@projection.ProjectionScreen::Scr001).is_empty(),
  )
}

test "InMemoryProjectionRepository/different_screens_stored_independently" {
  let repository = InMemoryProjectionRepository::new()
  let proj_001 = make_projection("p-001", @projection.ProjectionScreen::Scr001)
  let proj_003 = make_projection("p-003", @projection.ProjectionScreen::Scr003)
  repository.persist(proj_001)
  repository.persist(proj_003)
  match (
    repository.find_by_screen(@projection.ProjectionScreen::Scr001),
    repository.find_by_screen(@projection.ProjectionScreen::Scr003),
  ) {
    (Some(r001), Some(r003)) => {
      assert_eq!(r001.identifier, "p-001")
      assert_eq!(r003.identifier, "p-003")
    }
    _ => abort("Expected both projections to be found")
  }
}

test "InMemoryProjectionRepository/find_by_screen_returns_none_for_unregistered_screen" {
  let repository = InMemoryProjectionRepository::new()
  let proj = make_projection("proj-001", @projection.ProjectionScreen::Scr001)
  repository.persist(proj)
  assert_true!(
    repository.find_by_screen(@projection.ProjectionScreen::Scr003).is_empty(),
  )
}

// ============================================================================
// JwtTokenStore tests
// ============================================================================

fn make_token_record(expires_at : Int64) -> TokenRecord {
  {
    accessToken: "eyJhbGciOiJSUzI1NiJ9.test",
    expiresAt: expires_at,
    subject: "user-001",
    role: "admin",
    permissions: ["orders:approve", "orders:reject"],
  }
}

test "JwtTokenStore/status_absent_when_no_token_stored" {
  let store = JwtTokenStore::new()
  assert_eq!(store.status(1000L), TokenStatus::Absent)
}

test "JwtTokenStore/status_valid_when_token_not_yet_expired" {
  let store = JwtTokenStore::new()
  let token_record = make_token_record(2000L)
  store.store(token_record)
  assert_eq!(store.status(1000L), TokenStatus::Valid)
}

test "JwtTokenStore/status_expired_when_token_expiry_passed" {
  let store = JwtTokenStore::new()
  let token_record = make_token_record(500L)
  store.store(token_record)
  assert_eq!(store.status(1000L), TokenStatus::Expired)
}

test "JwtTokenStore/status_expired_at_exact_expiry_epoch" {
  let store = JwtTokenStore::new()
  let token_record = make_token_record(1000L)
  store.store(token_record)
  // At exactly expiresAt, token is NOT valid (strict >)
  assert_eq!(store.status(1000L), TokenStatus::Expired)
}

test "JwtTokenStore/access_token_returns_none_when_absent" {
  let store = JwtTokenStore::new()
  assert_true!(store.access_token(1000L).is_empty())
}

test "JwtTokenStore/access_token_returns_some_when_valid" {
  let store = JwtTokenStore::new()
  let token_record = make_token_record(2000L)
  store.store(token_record)
  match store.access_token(1000L) {
    Some(token) => assert_eq!(token, "eyJhbGciOiJSUzI1NiJ9.test")
    None => abort("Expected Some token when valid")
  }
}

test "JwtTokenStore/access_token_returns_none_when_expired" {
  let store = JwtTokenStore::new()
  let token_record = make_token_record(500L)
  store.store(token_record)
  assert_true!(store.access_token(1000L).is_empty())
}

test "JwtTokenStore/clear_removes_stored_token" {
  let store = JwtTokenStore::new()
  let token_record = make_token_record(2000L)
  store.store(token_record)
  store.clear()
  assert_eq!(store.status(1000L), TokenStatus::Absent)
}

test "JwtTokenStore/store_replaces_previous_token" {
  let store = JwtTokenStore::new()
  let first_record = make_token_record(500L)
  store.store(first_record)
  let second_record = make_token_record(2000L)
  store.store(second_record)
  assert_eq!(store.status(1000L), TokenStatus::Valid)
}

test "JwtTokenStore/record_returns_none_when_empty" {
  let store = JwtTokenStore::new()
  assert_true!(store.record().is_empty())
}

test "JwtTokenStore/record_returns_stored_record_regardless_of_expiry" {
  let store = JwtTokenStore::new()
  let token_record = make_token_record(500L)
  store.store(token_record)
  // expired but record is still accessible for claim reading
  match store.record() {
    Some(stored_record) => assert_eq!(stored_record.subject, "user-001")
    None => abort("Expected Some record after store")
  }
}

// ============================================================================
// ProblemDetail / parse_reason_code tests
// ============================================================================

test "parse_reason_code/auth_unauthorized_variants" {
  assert_eq!(
    parse_reason_code("AUTH_UNAUTHORIZED"),
    @command.ReasonCode::AuthUnauthorized,
  )
  assert_eq!(
    parse_reason_code("AUTH_INVALID_CREDENTIALS"),
    @command.ReasonCode::AuthUnauthorized,
  )
  assert_eq!(
    parse_reason_code("AUTH_TOKEN_EXPIRED"),
    @command.ReasonCode::AuthUnauthorized,
  )
  assert_eq!(
    parse_reason_code("AUTH_FORBIDDEN"),
    @command.ReasonCode::AuthUnauthorized,
  )
}

test "parse_reason_code/operation_not_allowed" {
  assert_eq!(
    parse_reason_code("OPERATION_NOT_ALLOWED"),
    @command.ReasonCode::OperationNotAllowed,
  )
}

test "parse_reason_code/duplicate_command" {
  assert_eq!(
    parse_reason_code("DUPLICATE_COMMAND"),
    @command.ReasonCode::DuplicateCommand,
  )
}

test "parse_reason_code/request_validation_failed" {
  assert_eq!(
    parse_reason_code("REQUEST_VALIDATION_FAILED"),
    @command.ReasonCode::RequestValidationFailed,
  )
}

test "parse_reason_code/resource_not_found" {
  assert_eq!(
    parse_reason_code("RESOURCE_NOT_FOUND"),
    @command.ReasonCode::ResourceNotFound,
  )
}

test "parse_reason_code/state_conflict" {
  assert_eq!(
    parse_reason_code("STATE_CONFLICT"),
    @command.ReasonCode::StateConflict,
  )
}

test "parse_reason_code/kill_switch_enabled" {
  assert_eq!(
    parse_reason_code("KILL_SWITCH_ENABLED"),
    @command.ReasonCode::KillSwitchEnabled,
  )
}

test "parse_reason_code/unknown_falls_back_to_internal_error" {
  assert_eq!(
    parse_reason_code("SOME_UNKNOWN_CODE"),
    @command.ReasonCode::InternalError,
  )
  assert_eq!(parse_reason_code(""), @command.ReasonCode::InternalError)
}

test "new_problem_detail/constructs_correctly" {
  let problem = new_problem_detail(
    403,
    "Forbidden",
    "required permission: orders:approve",
    Some("trace-001"),
    "AUTH_FORBIDDEN",
    false,
  )
  assert_eq!(problem.status, 403)
  assert_eq!(problem.title, "Forbidden")
  assert_eq!(problem.reasonCode, @command.ReasonCode::AuthUnauthorized)
  assert_eq!(problem.retryable, false)
  match problem.trace {
    Some(trace_value) => assert_eq!(trace_value, "trace-001")
    None => abort("Expected trace to be Some")
  }
}

test "new_problem_detail/without_trace" {
  let problem = new_problem_detail(
    500,
    "Internal Error",
    "unexpected",
    None,
    "INTERNAL_ERROR",
    true,
  )
  assert_true!(problem.trace.is_empty())
  assert_eq!(problem.reasonCode, @command.ReasonCode::InternalError)
  assert_eq!(problem.retryable, true)
}

test "is_retryable_status/5xx_is_retryable" {
  assert_true!(is_retryable_status(500))
  assert_true!(is_retryable_status(502))
  assert_true!(is_retryable_status(503))
  assert_true!(is_retryable_status(599))
}

test "is_retryable_status/4xx_is_not_retryable" {
  assert_false!(is_retryable_status(400))
  assert_false!(is_retryable_status(401))
  assert_false!(is_retryable_status(403))
  assert_false!(is_retryable_status(404))
  assert_false!(is_retryable_status(422))
}

test "is_retryable_status/2xx_is_not_retryable" {
  assert_false!(is_retryable_status(200))
  assert_false!(is_retryable_status(201))
}
