///| Domain policies and repository ports for the frontend domain.
///| Pure functions — no HTTP, no IO, no @mars, no @sol imports.

// ============================================================================
// Domain Events
// ============================================================================

/// Domain events emitted within the frontend bounded context.
/// Reference operations (find_by_screen etc.) do NOT emit events (RULE-FE-006).
pub(all) enum UiDomainEvent {
  CommandSubmitted(
    @session.CommandType,
    String,
    @command.CommandTarget?,
    String
  )
  CommandCompleted(
    @command.CommandStatus,
    Int?,
    @command.ReasonCode?,
    String
  )
  ProjectionRefreshed(
    @projection.ProjectionScreen,
    @projection.ProjectionStatus,
    Int,
    String
  )
} derive(Show)

// ============================================================================
// Repository Ports (traits / interfaces)
// ============================================================================

/// Repository port: UiSession persistence interface.
/// Implementations live in the infra layer (#73).
pub trait UiSessionRepository {
  find(Self, String) -> @session.UiSession?
  persist(Self, @session.UiSession) -> Unit
  terminate(Self, String) -> Unit
}

/// Repository port: ReadModelProjection persistence interface.
/// Implementations live in the infra layer (#73).
pub trait ProjectionRepository {
  find_by_screen(Self, @projection.ProjectionScreen) -> @projection.ReadModelProjection?
  persist(Self, @projection.ReadModelProjection) -> Unit
  terminate(Self, String) -> Unit
}

// ============================================================================
// OperationAvailabilityPolicy
// ============================================================================

/// Pure domain policy: determine if a command intent is allowed given the current session state.
/// Checks kill switch state and permission-based guards.
/// No HTTP calls, no IO.
pub fn check_operation_availability(
  session : @session.UiSession,
  intent : @command.CommandIntent
) -> Bool {
  // Unauthenticated or expired sessions cannot perform any command
  if session.authState != @session.AuthState::Authenticated {
    return false
  }
  // Kill switch blocks order-related operations
  let operation_guard = session.operationGuardState
  if operation_guard.killSwitch == @session.KillSwitchState::Enabled {
    let blocked = is_order_related_command(intent.commandType)
    if blocked {
      return false
    }
  }
  // Check if command type is in the explicitly disabled actions list
  let mut explicitly_disabled = false
  for disabled_type in operation_guard.disabledActions {
    if disabled_type == intent.commandType {
      explicitly_disabled = true
    }
  }
  if explicitly_disabled {
    return false
  }
  true
}

/// Returns true if the command type is order-related (blocked by kill switch).
/// Kill switch blocks Approve, Reject, and Retry operations.
fn is_order_related_command(command_type : @session.CommandType) -> Bool {
  match command_type {
    @session.CommandType::Approve
    | @session.CommandType::Reject
    | @session.CommandType::Retry => true
    _ => false
  }
}

// ============================================================================
// CommandDeduplicationPolicy
// ============================================================================

/// Pure domain policy: check if a submission is a duplicate of an in-flight interaction.
/// No UI rendering, no IO.
pub fn is_duplicate(
  submission_identifier : String,
  in_flight : Array[@command.CommandInteraction]
) -> Bool {
  @command.is_duplicate(submission_identifier, in_flight)
}

// ============================================================================
// ActionAllowedSpecification
// ============================================================================

/// Specification: determines if an action is allowed for the current session.
/// Combines authentication check with operation availability.
pub fn is_satisfied_by(
  session : @session.UiSession,
  intent : @command.CommandIntent
) -> Bool {
  check_operation_availability(session, intent)
}

// ============================================================================
// CommandIntentFactory
// ============================================================================

/// Factory: create a CommandIntent from command type and optional target.
pub fn create(
  command_type : @session.CommandType,
  target : @command.CommandTarget?
) -> @command.CommandIntent {
  let identifier = "intent"
  @command.create_command_intent(identifier, command_type, target)
}
