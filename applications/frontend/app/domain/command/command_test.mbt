///| Unit tests for CommandInteraction aggregate.

fn make_interaction(
  submission_identifier : String,
  trace_value : String,
  target : CommandTarget?,
  status : CommandStatus
) -> CommandInteraction {
  {
    identifier: "cmd-001",
    submissionIdentifier: submission_identifier,
    trace: trace_value,
    commandType: @session.CommandType::Approve,
    target,
    status,
    responseCode: None,
    reasonCode: None,
    actionReasonCode: None,
  }
}

fn make_target(target_identifier : String) -> CommandTarget {
  { targetIdentifier: target_identifier, targetType: "order" }
}

/// TST-FE-002: submit_command with empty trace returns Err(MissingRequired).
test "submit_command/empty_trace_returns_error" {
  let interaction = make_interaction("sub-001", "", None, CommandStatus::Draft)
  let result = submit_command(interaction, [])
  match result {
    Err(@session.DomainError::MissingRequired(_)) => ()
    _ => abort("Expected MissingRequired error for empty trace")
  }
}

/// TST-FE-002: submit_command with empty target identifier returns Err(MissingRequired).
test "submit_command/empty_target_identifier_returns_error" {
  let target = make_target("")
  let interaction = make_interaction(
    "sub-001",
    "trace-abc",
    Some(target),
    CommandStatus::Draft,
  )
  let result = submit_command(interaction, [])
  match result {
    Err(@session.DomainError::MissingRequired(_)) => ()
    _ => abort("Expected MissingRequired error for empty target identifier")
  }
}

/// TST-FE-005: submit_command with same submissionIdentifier as in-flight interaction returns Err.
test "submit_command/duplicate_submission_returns_error" {
  let in_flight_interaction = make_interaction(
    "sub-dup",
    "trace-existing",
    None,
    CommandStatus::Submitting,
  )
  let new_interaction = make_interaction("sub-dup", "trace-new", None, CommandStatus::Draft)
  let result = submit_command(new_interaction, [in_flight_interaction])
  match result {
    Err(@session.DomainError::DuplicateSubmission(_)) => ()
    _ => abort("Expected DuplicateSubmission error")
  }
}

/// TST-FE-005: is_duplicate correctly identifies a duplicate submission.
test "is_duplicate/detects_submitting_duplicate" {
  let in_flight_interaction = make_interaction(
    "sub-dup",
    "trace-001",
    None,
    CommandStatus::Submitting,
  )
  assert_true!(is_duplicate("sub-dup", [in_flight_interaction]))
  assert_false!(is_duplicate("sub-different", [in_flight_interaction]))
}

/// TST-FE-005: is_duplicate ignores non-Submitting interactions.
test "is_duplicate/ignores_non_submitting" {
  let accepted_interaction = make_interaction(
    "sub-dup",
    "trace-001",
    None,
    CommandStatus::Accepted,
  )
  assert_false!(is_duplicate("sub-dup", [accepted_interaction]))
}

/// Happy path: submit_command with valid trace and target transitions to Submitting.
test "submit_command/valid_submission_transitions_to_submitting" {
  let target = make_target("order-001")
  let interaction = make_interaction(
    "sub-001",
    "trace-abc",
    Some(target),
    CommandStatus::Draft,
  )
  let result = submit_command(interaction, [])
  match result {
    Ok(submitted) => assert_eq!(submitted.status, CommandStatus::Submitting)
    Err(_) => abort("Expected Ok")
  }
}

/// Happy path: mark_duplicate transitions Draft interaction to Duplicate.
test "mark_duplicate/draft_transitions_to_duplicate" {
  let interaction = make_interaction("sub-001", "trace-abc", None, CommandStatus::Draft)
  let result = mark_duplicate(interaction)
  match result {
    Ok(duplicated) => assert_eq!(duplicated.status, CommandStatus::Duplicate)
    Err(_) => abort("Expected Ok")
  }
}

/// acknowledge transitions Submitting → Accepted.
test "acknowledge/submitting_to_accepted" {
  let interaction = make_interaction(
    "sub-001",
    "trace-abc",
    None,
    CommandStatus::Submitting,
  )
  let result = acknowledge(interaction, 200)
  match result {
    Ok(accepted) => assert_eq!(accepted.status, CommandStatus::Accepted)
    Err(_) => abort("Expected Ok")
  }
}
