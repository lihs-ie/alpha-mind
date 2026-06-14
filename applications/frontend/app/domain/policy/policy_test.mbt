///| Unit tests for domain policies.

fn make_session_with_kill_switch(
  kill_switch : @session.KillSwitchState
) -> @session.UiSession {
  {
    identifier: "sess-001",
    user: Some("user-001"),
    authState: @session.AuthState::Authenticated,
    permissionSnapshot: None,
    currentScreen: @session.Screen::Scr003,
    trace: None,
    updatedAt: "2026-01-01T00:00:00Z",
    operationGuardState: {
      killSwitch: kill_switch,
      disabledActions: [],
    },
    screenContexts: [],
  }
}

fn make_intent(command_type : @session.CommandType) -> @command.CommandIntent {
  @command.create_command_intent("intent-001", command_type, None)
}

/// TST-FE-003: kill switch Enabled blocks Approve operation.
test "check_operation_availability/kill_switch_enabled_blocks_approve" {
  let session = make_session_with_kill_switch(@session.KillSwitchState::Enabled)
  let intent = make_intent(@session.CommandType::Approve)
  assert_false!(check_operation_availability(session, intent))
}

/// TST-FE-003: kill switch Enabled blocks Reject operation.
test "check_operation_availability/kill_switch_enabled_blocks_reject" {
  let session = make_session_with_kill_switch(@session.KillSwitchState::Enabled)
  let intent = make_intent(@session.CommandType::Reject)
  assert_false!(check_operation_availability(session, intent))
}

/// TST-FE-003: kill switch Enabled blocks Retry operation.
test "check_operation_availability/kill_switch_enabled_blocks_retry" {
  let session = make_session_with_kill_switch(@session.KillSwitchState::Enabled)
  let intent = make_intent(@session.CommandType::Retry)
  assert_false!(check_operation_availability(session, intent))
}

/// kill switch Disabled allows Approve operation.
test "check_operation_availability/kill_switch_disabled_allows_approve" {
  let session = make_session_with_kill_switch(@session.KillSwitchState::Disabled)
  let intent = make_intent(@session.CommandType::Approve)
  assert_true!(check_operation_availability(session, intent))
}

/// kill switch Enabled still allows non-order commands (e.g., RunCycle).
test "check_operation_availability/kill_switch_enabled_allows_run_cycle" {
  let session = make_session_with_kill_switch(@session.KillSwitchState::Enabled)
  let intent = make_intent(@session.CommandType::RunCycle)
  assert_true!(check_operation_availability(session, intent))
}

/// Unauthenticated session blocks all operations.
test "check_operation_availability/unauthenticated_blocks_all" {
  let unauthenticated_session = make_session_with_kill_switch(@session.KillSwitchState::Disabled)
  // Override auth state via expire simulation using session transition helper
  let session : @session.UiSession = {
    identifier: unauthenticated_session.identifier,
    user: None,
    authState: @session.AuthState::Unauthenticated,
    permissionSnapshot: None,
    currentScreen: @session.Screen::Scr000,
    trace: None,
    updatedAt: "2026-01-01T00:00:00Z",
    operationGuardState: unauthenticated_session.operationGuardState,
    screenContexts: [],
  }
  let intent = make_intent(@session.CommandType::Approve)
  assert_false!(check_operation_availability(session, intent))
}

/// is_satisfied_by delegates to check_operation_availability.
test "is_satisfied_by/delegates_to_availability_check" {
  let session = make_session_with_kill_switch(@session.KillSwitchState::Disabled)
  let intent = make_intent(@session.CommandType::Approve)
  assert_true!(is_satisfied_by(session, intent))
}

/// is_duplicate delegates to command.is_duplicate.
test "is_duplicate/detects_in_flight_duplicate" {
  let in_flight : Array[@command.CommandInteraction] = [
    {
      identifier: "cmd-001",
      submissionIdentifier: "sub-dup",
      trace: "trace-001",
      commandType: @session.CommandType::Approve,
      target: None,
      status: @command.CommandStatus::Submitting,
      responseCode: None,
      reasonCode: None,
      actionReasonCode: None,
    },
  ]
  assert_true!(is_duplicate("sub-dup", in_flight))
  assert_false!(is_duplicate("sub-other", in_flight))
}

/// CommandIntentFactory::create generates a CommandIntent.
test "create/generates_command_intent" {
  let intent = create(@session.CommandType::Promote, None)
  assert_eq!(intent.commandType, @session.CommandType::Promote)
}
