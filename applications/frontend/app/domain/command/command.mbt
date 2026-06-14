///| CommandInteraction aggregate — update command intent, submission state, deduplication.
///| INV-FE-002: trace and target identifier required on submit.
///| INV-FE-003: same submissionIdentifier submitted only once.

/// Reason code for command failure responses.
pub(all) enum ReasonCode {
  AuthUnauthorized
  OperationNotAllowed
  DuplicateCommand
  RequestValidationFailed
  ResourceNotFound
  StateConflict
  KillSwitchEnabled
  InternalError
} derive(Eq, Show)

/// Operator-provided reason code for an action (e.g., why rejecting an order).
pub(all) enum OperatorActionReasonCode {
  RiskThresholdExceeded
  PolicyViolation
  ManualOverride
  Other
} derive(Eq, Show)

/// Command submission status.
pub(all) enum CommandStatus {
  Draft
  Submitting
  Accepted
  Rejected
  Duplicate
} derive(Eq, Show)

/// Value object: identifies the target of a command operation.
pub(all) struct CommandTarget {
  targetIdentifier : String
  targetType : String
} derive(Eq, Show)

/// CommandInteraction aggregate root.
pub(all) struct CommandInteraction {
  identifier : String
  submissionIdentifier : String
  trace : String
  commandType : @session.CommandType
  target : CommandTarget?
  status : CommandStatus
  responseCode : Int?
  reasonCode : ReasonCode?
  actionReasonCode : OperatorActionReasonCode?
} derive(Show)

/// CommandIntent entity — represents a draft before submission.
pub(all) struct CommandIntent {
  identifier : String
  commandType : @session.CommandType
  target : CommandTarget?
} derive(Show)

/// Factory: create a CommandIntent from type and optional target.
pub fn create_command_intent(
  identifier : String,
  command_type : @session.CommandType,
  target : CommandTarget?
) -> CommandIntent {
  { identifier, commandType: command_type, target }
}

/// Transition: Draft → Submitting (submit_command).
/// INV-FE-002: trace must be non-empty; if target is present, targetIdentifier must be non-empty.
pub fn submit_command(
  interaction : CommandInteraction,
  in_flight : Array[CommandInteraction]
) -> Result[CommandInteraction, @session.DomainError] {
  if interaction.trace == "" {
    return Err(@session.DomainError::MissingRequired("trace must not be empty"))
  }
  match interaction.target {
    Some(target_value) =>
      if target_value.targetIdentifier == "" {
        return Err(
          @session.DomainError::MissingRequired("target identifier must not be empty"),
        )
      }
    None => ()
  }
  if is_duplicate(interaction.submissionIdentifier, in_flight) {
    return Err(
      @session.DomainError::DuplicateSubmission(
        "A submission with the same submissionIdentifier is already in flight",
      ),
    )
  }
  Ok({ ..interaction, status: CommandStatus::Submitting })
}

/// Transition: Submitting → Accepted.
pub fn acknowledge(
  interaction : CommandInteraction,
  response_code : Int
) -> Result[CommandInteraction, @session.DomainError] {
  match interaction.status {
    CommandStatus::Submitting =>
      Ok({ ..interaction, status: CommandStatus::Accepted, responseCode: Some(response_code) })
    _ =>
      Err(
        @session.DomainError::InvalidTransition(
          "Can only acknowledge a Submitting interaction",
        ),
      )
  }
}

/// Transition: Submitting → Rejected.
pub fn reject_command(
  interaction : CommandInteraction,
  response_code : Int,
  reason_code : ReasonCode
) -> Result[CommandInteraction, @session.DomainError] {
  match interaction.status {
    CommandStatus::Submitting =>
      Ok({
        ..interaction,
        status: CommandStatus::Rejected,
        responseCode: Some(response_code),
        reasonCode: Some(reason_code),
      })
    _ =>
      Err(
        @session.DomainError::InvalidTransition("Can only reject a Submitting interaction"),
      )
  }
}

/// Transition: mark interaction as Duplicate (INV-FE-003).
pub fn mark_duplicate(
  interaction : CommandInteraction
) -> Result[CommandInteraction, @session.DomainError] {
  match interaction.status {
    CommandStatus::Submitting | CommandStatus::Draft =>
      Ok({ ..interaction, status: CommandStatus::Duplicate })
    _ =>
      Err(
        @session.DomainError::InvalidTransition(
          "Can only mark a Draft or Submitting interaction as Duplicate",
        ),
      )
  }
}

/// Pure deduplication check: returns true if submissionIdentifier already exists
/// among in-flight (Submitting) interactions.
/// INV-FE-003: same submissionIdentifier must be sent only once.
pub fn is_duplicate(
  submission_identifier : String,
  in_flight : Array[CommandInteraction]
) -> Bool {
  let mut found = false
  for interaction in in_flight {
    if interaction.submissionIdentifier == submission_identifier &&
      interaction.status == CommandStatus::Submitting {
      found = true
    }
  }
  found
}
