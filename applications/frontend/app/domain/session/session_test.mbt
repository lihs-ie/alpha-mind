///| Unit tests for UiSession aggregate.

fn make_session(auth_state : AuthState) -> UiSession {
  {
    identifier: "sess-001",
    user: None,
    authState: auth_state,
    permissionSnapshot: None,
    currentScreen: Screen::Scr000,
    trace: None,
    updatedAt: "2026-01-01T00:00:00Z",
    operationGuardState: {
      killSwitch: KillSwitchState::Disabled,
      disabledActions: [],
    },
    screenContexts: [],
  }
}

fn make_permission_snapshot() -> PermissionSnapshot {
  { role: Role::Admin, permissions: [] }
}

/// TST-FE-001: navigate_screen from Unauthenticated to protected screen returns Err.
test "navigate_screen/unauthenticated_to_protected_returns_error" {
  let session = make_session(AuthState::Unauthenticated)
  let result = navigate_screen(session, Screen::Scr001, "2026-01-01T00:00:01Z")
  assert_true!(result.is_err())
  match result {
    Err(DomainError::ProtectedScreenBlocked(_)) => ()
    _ => abort("Expected ProtectedScreenBlocked error")
  }
}

/// TST-FE-001: navigate_screen from Unauthenticated to public screen (Scr000) returns Ok.
test "navigate_screen/unauthenticated_to_public_screen_ok" {
  let session = make_session(AuthState::Unauthenticated)
  let result = navigate_screen(session, Screen::Scr000, "2026-01-01T00:00:01Z")
  assert_true!(result.is_ok())
}

/// Happy path: authenticate Unauthenticated → Authenticated returns Ok.
test "authenticate/unauthenticated_to_authenticated_ok" {
  let session = make_session(AuthState::Unauthenticated)
  let snapshot = make_permission_snapshot()
  let result = authenticate(session, "user-001", snapshot, "2026-01-01T00:00:01Z")
  assert_true!(result.is_ok())
  match result {
    Ok(updated_session) => assert_eq!(updated_session.authState, AuthState::Authenticated)
    Err(_) => abort("Expected Ok")
  }
}

/// authenticate called on already-Authenticated session returns Err.
test "authenticate/already_authenticated_returns_error" {
  let session = make_session(AuthState::Authenticated)
  let snapshot = make_permission_snapshot()
  let result = authenticate(session, "user-001", snapshot, "2026-01-01T00:00:01Z")
  assert_true!(result.is_err())
  match result {
    Err(DomainError::InvalidTransition(_)) => ()
    _ => abort("Expected InvalidTransition error")
  }
}

/// Authenticated session can navigate to protected screen.
test "navigate_screen/authenticated_to_protected_ok" {
  let session = make_session(AuthState::Authenticated)
  let result = navigate_screen(session, Screen::Scr003, "2026-01-01T00:00:01Z")
  assert_true!(result.is_ok())
}

/// expire_session transitions Authenticated → Expired.
test "expire_session/authenticated_to_expired_ok" {
  let session = make_session(AuthState::Authenticated)
  let result = expire_session(session, "2026-01-01T00:00:01Z")
  assert_true!(result.is_ok())
  match result {
    Ok(updated_session) => assert_eq!(updated_session.authState, AuthState::Expired)
    Err(_) => abort("Expected Ok")
  }
}

/// Expired session cannot navigate to protected screen.
test "navigate_screen/expired_to_protected_returns_error" {
  let session = make_session(AuthState::Expired)
  let result = navigate_screen(session, Screen::Scr001, "2026-01-01T00:00:01Z")
  assert_true!(result.is_err())
}
