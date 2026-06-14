///| UiSession aggregate — authentication state, permissions, screen navigation.
///| INV-FE-001: unauthenticated sessions cannot navigate to protected screens.

/// Authentication state of the session.
pub(all) enum AuthState {
  Unauthenticated
  Authenticated
  Expired
} derive(Eq, Show)

/// Screen identifiers (SCR-000..SCR-007).
pub(all) enum Screen {
  Scr000
  Scr001
  Scr002
  Scr003
  Scr004
  Scr005
  Scr006
  Scr007
} derive(Eq, Show)

/// Status of an individual screen context.
pub(all) enum ScreenContextStatus {
  Initial
  Loading
  Ready
  Error
} derive(Eq, Show)

/// Screen context entity tracking per-screen display/operation state.
pub(all) struct ScreenContext {
  identifier : String
  screen : Screen
  status : ScreenContextStatus
} derive(Eq, Show)

/// Kill switch state.
pub(all) enum KillSwitchState {
  Enabled
  Disabled
} derive(Eq, Show)

/// Role assigned to the authenticated user.
pub(all) enum Role {
  Admin
  Viewer
} derive(Eq, Show)

/// A single permission string (newtype wrapper for clarity).
pub(all) struct Permission {
  value : String
} derive(Eq, Show)

/// Snapshot of permissions at the time of an operation.
pub(all) struct PermissionSnapshot {
  role : Role
  permissions : Array[Permission]
} derive(Show)

/// Command type enum — shared with command package via policy package.
/// Defined here to avoid circular dependency; used in policy/command packages.
pub(all) enum CommandType {
  Approve
  Reject
  Retry
  RunCycle
  KillSwitch
  Promote
  Hypothesize
  Adopt
} derive(Eq, Show)

/// Operation guard state — kill switch and disabled actions.
pub(all) struct OperationGuardState {
  killSwitch : KillSwitchState
  disabledActions : Array[CommandType]
} derive(Show)

/// UiSession aggregate root.
pub(all) struct UiSession {
  identifier : String
  user : String?
  authState : AuthState
  permissionSnapshot : PermissionSnapshot?
  currentScreen : Screen
  trace : String?
  updatedAt : String
  operationGuardState : OperationGuardState
  screenContexts : Array[ScreenContext]
} derive(Show)

/// Domain error variants for session transitions.
pub(all) enum DomainError {
  InvalidTransition(String)
  MissingRequired(String)
  DuplicateSubmission(String)
  ProtectedScreenBlocked(String)
} derive(Eq, Show)

/// Returns true if the screen is a protected screen (requires authentication).
/// SCR-000 (login) is public; SCR-001..SCR-007 are protected.
pub fn is_protected_screen(screen : Screen) -> Bool {
  match screen {
    Screen::Scr000 => false
    _ => true
  }
}

/// Transition: Unauthenticated → Authenticated.
/// Rejects if already Authenticated or Expired.
pub fn authenticate(
  session : UiSession,
  user : String,
  permission_snapshot : PermissionSnapshot,
  updated_at : String
) -> Result[UiSession, DomainError] {
  match session.authState {
    AuthState::Unauthenticated =>
      Ok({
        ..session,
        authState: AuthState::Authenticated,
        user: Some(user),
        permissionSnapshot: Some(permission_snapshot),
        updatedAt: updated_at,
      })
    AuthState::Authenticated =>
      Err(DomainError::InvalidTransition("Session is already authenticated"))
    AuthState::Expired =>
      Err(DomainError::InvalidTransition("Cannot authenticate an expired session"))
  }
}

/// Transition: Authenticated → Expired.
pub fn expire_session(
  session : UiSession,
  updated_at : String
) -> Result[UiSession, DomainError] {
  match session.authState {
    AuthState::Authenticated =>
      Ok({ ..session, authState: AuthState::Expired, updatedAt: updated_at })
    _ =>
      Err(DomainError::InvalidTransition("Session must be Authenticated to expire"))
  }
}

/// Transition: navigate to a new screen.
/// INV-FE-001: protected screens require Authenticated state.
pub fn navigate_screen(
  session : UiSession,
  screen : Screen,
  updated_at : String
) -> Result[UiSession, DomainError] {
  if is_protected_screen(screen) && session.authState != AuthState::Authenticated {
    Err(
      DomainError::ProtectedScreenBlocked(
        "Cannot navigate to protected screen when unauthenticated or expired",
      ),
    )
  } else {
    Ok({ ..session, currentScreen: screen, updatedAt: updated_at })
  }
}

/// Start loading a specific screen context.
pub fn start_loading_screen_context(context : ScreenContext) -> ScreenContext {
  { ..context, status: ScreenContextStatus::Loading }
}

/// Apply projection to a screen context (transition to Ready).
pub fn apply_projection_to_screen_context(context : ScreenContext) -> ScreenContext {
  { ..context, status: ScreenContextStatus::Ready }
}

/// Mark a screen context as failed.
pub fn fail_screen_context(context : ScreenContext) -> ScreenContext {
  { ..context, status: ScreenContextStatus::Error }
}
