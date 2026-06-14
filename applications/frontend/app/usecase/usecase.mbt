///| Usecase layer — application services for the frontend bounded context.
///|
///| Each service orchestrates domain operations via domain repository ports (traits).
///| No HTTP calls, no IO, no Sol/Mars imports are allowed here.
///| Actual port implementations live in the infra layer (#73).
///|
///| Invariants enforced at this layer:
///| - RULE-FE-001: authentication guard before protected operations
///| - RULE-FE-002: trace + target identifier required on submit
///| - RULE-FE-003: kill switch blocks order-related operations
///| - RULE-FE-005: deduplication via submissionIdentifier

// ============================================================================
// UsecaseError — application-level error envelope
// ============================================================================

/// Application-level error returned by usecase services.
/// Domain errors are wrapped in DomainViolation; validation failures in Validation.
pub(all) enum UsecaseError {
  DomainViolation(@session.DomainError)
  Unauthorized(String)
  OperationBlocked(String)
  DuplicateSubmission(String)
  Validation(String)
} derive(Eq, Show)

// ============================================================================
// AuthenticationService — SCR-000 login and token management
// ============================================================================

/// Input for the Login usecase.
pub(all) struct LoginInput {
  user : String
  role : @session.Role
  permissions : Array[@session.Permission]
  updatedAt : String
} derive(Show)

/// Output of a successful Login.
pub(all) struct LoginOutput {
  session : @session.UiSession
} derive(Show)

/// Authenticate a user into an existing session.
/// RULE-FE-001: only Unauthenticated sessions can be authenticated.
/// Returns updated UiSession on success or a UsecaseError on failure.
pub fn login[R : @policy.UiSessionRepository](
  repository : R,
  session_identifier : String,
  input : LoginInput
) -> Result[LoginOutput, UsecaseError] {
  let session = match repository.find(session_identifier) {
    Some(s) => s
    None => new_session(session_identifier, input.updatedAt)
  }
  let permission_snapshot : @session.PermissionSnapshot = {
    role: input.role,
    permissions: input.permissions,
  }
  match @session.authenticate(session, input.user, permission_snapshot, input.updatedAt) {
    Ok(updated_session) => {
      repository.persist(updated_session)
      Ok({ session: updated_session })
    }
    Err(domain_error) => Err(UsecaseError::DomainViolation(domain_error))
  }
}

/// Expire the current session (e.g., on token expiry or explicit logout).
/// RULE-FE-001: only Authenticated sessions can be expired.
pub fn logout[R : @policy.UiSessionRepository](
  repository : R,
  session_identifier : String,
  updated_at : String
) -> Result[Unit, UsecaseError] {
  let session = match repository.find(session_identifier) {
    Some(s) => s
    None => return Err(UsecaseError::Unauthorized("Session not found"))
  }
  match @session.expire_session(session, updated_at) {
    Ok(updated_session) => {
      repository.persist(updated_session)
      Ok(())
    }
    Err(domain_error) => Err(UsecaseError::DomainViolation(domain_error))
  }
}

/// Navigate the session to a target screen.
/// RULE-FE-001: protected screens require Authenticated state.
pub fn navigate[R : @policy.UiSessionRepository](
  repository : R,
  session_identifier : String,
  screen : @session.Screen,
  updated_at : String
) -> Result[@session.UiSession, UsecaseError] {
  let session = match repository.find(session_identifier) {
    Some(s) => s
    None => return Err(UsecaseError::Unauthorized("Session not found"))
  }
  match @session.navigate_screen(session, screen, updated_at) {
    Ok(updated_session) => {
      repository.persist(updated_session)
      Ok(updated_session)
    }
    Err(domain_error) => Err(UsecaseError::DomainViolation(domain_error))
  }
}

// ============================================================================
// DashboardQueryService — SCR-001 read projection
// ============================================================================

/// Input for loading the dashboard projection.
pub(all) struct LoadDashboardInput {
  screen : @projection.ProjectionScreen
  updatedAt : String
} derive(Show)

/// Load (or initialize) the dashboard projection, marking it as Loading.
/// RULE-FE-006: query operations do NOT emit state-change domain events.
pub fn load_dashboard[P : @policy.ProjectionRepository](
  repository : P,
  input : LoadDashboardInput
) -> @projection.ReadModelProjection {
  let current = match repository.find_by_screen(input.screen) {
    Some(p) => p
    None => new_projection(input.screen, input.updatedAt)
  }
  let loading_projection = @projection.start_loading(current, input.updatedAt)
  repository.persist(loading_projection)
  loading_projection
}

/// Refresh the dashboard projection with new items and summary from the ACL layer.
/// RULE-FE-004: only domain-defined ViewItem / ViewSummary types are stored (no raw DTOs).
pub fn refresh_dashboard[P : @policy.ProjectionRepository](
  repository : P,
  screen : @projection.ProjectionScreen,
  items : Array[@projection.ViewItem],
  summary : @projection.ViewSummary?,
  pagination : @projection.Pagination?,
  updated_at : String
) -> @projection.ReadModelProjection {
  let current = match repository.find_by_screen(screen) {
    Some(p) => p
    None => new_projection(screen, updated_at)
  }
  let refreshed = @projection.refresh_projection(
    current,
    items,
    summary,
    pagination,
    updated_at,
  )
  repository.persist(refreshed)
  refreshed
}

/// Mark the dashboard projection as failed.
pub fn fail_dashboard[P : @policy.ProjectionRepository](
  repository : P,
  screen : @projection.ProjectionScreen,
  updated_at : String
) -> @projection.ReadModelProjection {
  let current = match repository.find_by_screen(screen) {
    Some(p) => p
    None => new_projection(screen, updated_at)
  }
  let failed_projection = @projection.fail_projection(current, updated_at)
  repository.persist(failed_projection)
  failed_projection
}

// ============================================================================
// OrdersCommandService — SCR-003 approve / reject / retry
// ============================================================================

/// Input for approving an order.
/// RULE-FE-002: trace and orderIdentifier required.
pub(all) struct ApproveOrderInput {
  sessionIdentifier : String
  submissionIdentifier : String
  trace : String
  orderIdentifier : String
  updatedAt : String
} derive(Show)

/// Input for rejecting an order.
/// RULE-FE-002: trace and orderIdentifier required.
pub(all) struct RejectOrderInput {
  sessionIdentifier : String
  submissionIdentifier : String
  trace : String
  orderIdentifier : String
  actionReasonCode : @command.OperatorActionReasonCode
  updatedAt : String
} derive(Show)

/// Input for retrying a failed order.
pub(all) struct RetryOrderInput {
  sessionIdentifier : String
  submissionIdentifier : String
  trace : String
  orderIdentifier : String
  updatedAt : String
} derive(Show)

/// Validate and prepare an order approve command interaction.
/// RULE-FE-001: session must be Authenticated.
/// RULE-FE-003: kill switch must be disabled.
/// RULE-FE-005: deduplication via submissionIdentifier.
pub fn approve_order[R : @policy.UiSessionRepository](
  repository : R,
  input : ApproveOrderInput,
  in_flight : Array[@command.CommandInteraction]
) -> Result[@command.CommandInteraction, UsecaseError] {
  match require_authenticated_session(repository, input.sessionIdentifier) {
    Err(e) => Err(e)
    Ok(session) => {
      let intent = @policy.create(
        @session.CommandType::Approve,
        Some({ targetIdentifier: input.orderIdentifier, targetType: "order" }),
      )
      if not(@policy.is_satisfied_by(session, intent)) {
        Err(
          UsecaseError::OperationBlocked(
            "Approve is blocked (kill switch or permission denied)",
          ),
        )
      } else {
        let interaction : @command.CommandInteraction = {
          identifier: input.submissionIdentifier,
          submissionIdentifier: input.submissionIdentifier,
          trace: input.trace,
          commandType: @session.CommandType::Approve,
          target: Some({ targetIdentifier: input.orderIdentifier, targetType: "order" }),
          status: @command.CommandStatus::Draft,
          responseCode: None,
          reasonCode: None,
          actionReasonCode: None,
        }
        submit_interaction(interaction, in_flight)
      }
    }
  }
}

/// Validate and prepare an order reject command interaction.
/// RULE-FE-001: session must be Authenticated.
/// RULE-FE-003: kill switch must be disabled.
pub fn reject_order[R : @policy.UiSessionRepository](
  repository : R,
  input : RejectOrderInput,
  in_flight : Array[@command.CommandInteraction]
) -> Result[@command.CommandInteraction, UsecaseError] {
  match require_authenticated_session(repository, input.sessionIdentifier) {
    Err(e) => Err(e)
    Ok(session) => {
      let intent = @policy.create(
        @session.CommandType::Reject,
        Some({ targetIdentifier: input.orderIdentifier, targetType: "order" }),
      )
      if not(@policy.is_satisfied_by(session, intent)) {
        Err(
          UsecaseError::OperationBlocked(
            "Reject is blocked (kill switch or permission denied)",
          ),
        )
      } else {
        let interaction : @command.CommandInteraction = {
          identifier: input.submissionIdentifier,
          submissionIdentifier: input.submissionIdentifier,
          trace: input.trace,
          commandType: @session.CommandType::Reject,
          target: Some({ targetIdentifier: input.orderIdentifier, targetType: "order" }),
          status: @command.CommandStatus::Draft,
          responseCode: None,
          reasonCode: None,
          actionReasonCode: Some(input.actionReasonCode),
        }
        submit_interaction(interaction, in_flight)
      }
    }
  }
}

/// Validate and prepare an order retry command interaction.
pub fn retry_order[R : @policy.UiSessionRepository](
  repository : R,
  input : RetryOrderInput,
  in_flight : Array[@command.CommandInteraction]
) -> Result[@command.CommandInteraction, UsecaseError] {
  match require_authenticated_session(repository, input.sessionIdentifier) {
    Err(e) => Err(e)
    Ok(session) => {
      let intent = @policy.create(
        @session.CommandType::Retry,
        Some({ targetIdentifier: input.orderIdentifier, targetType: "order" }),
      )
      if not(@policy.is_satisfied_by(session, intent)) {
        Err(
          UsecaseError::OperationBlocked(
            "Retry is blocked (kill switch or permission denied)",
          ),
        )
      } else {
        let interaction : @command.CommandInteraction = {
          identifier: input.submissionIdentifier,
          submissionIdentifier: input.submissionIdentifier,
          trace: input.trace,
          commandType: @session.CommandType::Retry,
          target: Some({ targetIdentifier: input.orderIdentifier, targetType: "order" }),
          status: @command.CommandStatus::Draft,
          responseCode: None,
          reasonCode: None,
          actionReasonCode: None,
        }
        submit_interaction(interaction, in_flight)
      }
    }
  }
}

// ============================================================================
// AuditQueryService — SCR-004 audit log projection
// ============================================================================

/// Input for querying the audit log projection.
pub(all) struct QueryAuditLogsInput {
  screen : @projection.ProjectionScreen
  criteria : @projection.QueryCriteria
  updatedAt : String
} derive(Show)

/// Load the audit log projection, transitioning to Loading state.
/// RULE-FE-006: query does not emit state-change domain events.
pub fn load_audit_logs[P : @policy.ProjectionRepository](
  repository : P,
  input : QueryAuditLogsInput
) -> @projection.ReadModelProjection {
  let current = match repository.find_by_screen(input.screen) {
    Some(p) => p
    None => new_projection(input.screen, input.updatedAt)
  }
  let loading_projection = @projection.start_loading(current, input.updatedAt)
  repository.persist(loading_projection)
  loading_projection
}

// ============================================================================
// ModelValidationService — SCR-005 approve / reject model
// ============================================================================

/// Input for approving a model.
pub(all) struct ApproveModelInput {
  sessionIdentifier : String
  submissionIdentifier : String
  trace : String
  modelVersion : String
  updatedAt : String
} derive(Show)

/// Input for rejecting a model.
pub(all) struct RejectModelInput {
  sessionIdentifier : String
  submissionIdentifier : String
  trace : String
  modelVersion : String
  updatedAt : String
} derive(Show)

/// Validate and prepare an approve-model command interaction.
/// RULE-FE-001: session must be Authenticated.
pub fn approve_model[R : @policy.UiSessionRepository](
  repository : R,
  input : ApproveModelInput,
  in_flight : Array[@command.CommandInteraction]
) -> Result[@command.CommandInteraction, UsecaseError] {
  match require_authenticated_session(repository, input.sessionIdentifier) {
    Err(e) => Err(e)
    Ok(session) => {
      let intent = @policy.create(
        @session.CommandType::Promote,
        Some({ targetIdentifier: input.modelVersion, targetType: "model" }),
      )
      if not(@policy.is_satisfied_by(session, intent)) {
        Err(UsecaseError::OperationBlocked("Approve model is blocked by permission policy"))
      } else {
        let interaction : @command.CommandInteraction = {
          identifier: input.submissionIdentifier,
          submissionIdentifier: input.submissionIdentifier,
          trace: input.trace,
          commandType: @session.CommandType::Promote,
          target: Some({ targetIdentifier: input.modelVersion, targetType: "model" }),
          status: @command.CommandStatus::Draft,
          responseCode: None,
          reasonCode: None,
          actionReasonCode: None,
        }
        submit_interaction(interaction, in_flight)
      }
    }
  }
}

/// Validate and prepare a reject-model command interaction.
pub fn reject_model[R : @policy.UiSessionRepository](
  repository : R,
  input : RejectModelInput,
  in_flight : Array[@command.CommandInteraction]
) -> Result[@command.CommandInteraction, UsecaseError] {
  match require_authenticated_session(repository, input.sessionIdentifier) {
    Err(e) => Err(e)
    Ok(session) => {
      let intent = @policy.create(
        @session.CommandType::Reject,
        Some({ targetIdentifier: input.modelVersion, targetType: "model" }),
      )
      if not(@policy.is_satisfied_by(session, intent)) {
        Err(UsecaseError::OperationBlocked("Reject model is blocked by permission policy"))
      } else {
        let interaction : @command.CommandInteraction = {
          identifier: input.submissionIdentifier,
          submissionIdentifier: input.submissionIdentifier,
          trace: input.trace,
          commandType: @session.CommandType::Reject,
          target: Some({ targetIdentifier: input.modelVersion, targetType: "model" }),
          status: @command.CommandStatus::Draft,
          responseCode: None,
          reasonCode: None,
          actionReasonCode: None,
        }
        submit_interaction(interaction, in_flight)
      }
    }
  }
}

// ============================================================================
// InsightQueryService — SCR-006 insights projection + hypothesize
// ============================================================================

/// Input for loading the insights projection.
pub(all) struct LoadInsightsInput {
  screen : @projection.ProjectionScreen
  updatedAt : String
} derive(Show)

/// Input for hypothesizing an insight.
pub(all) struct HypothesizeInsightInput {
  sessionIdentifier : String
  submissionIdentifier : String
  trace : String
  insightIdentifier : String
  updatedAt : String
} derive(Show)

/// Load the insights projection into Loading state.
/// RULE-FE-006: no state-change events emitted.
pub fn load_insights[P : @policy.ProjectionRepository](
  repository : P,
  input : LoadInsightsInput
) -> @projection.ReadModelProjection {
  let current = match repository.find_by_screen(input.screen) {
    Some(p) => p
    None => new_projection(input.screen, input.updatedAt)
  }
  let loading_projection = @projection.start_loading(current, input.updatedAt)
  repository.persist(loading_projection)
  loading_projection
}

/// Validate and prepare a hypothesize-insight command interaction.
/// RULE-FE-001: session must be Authenticated.
pub fn hypothesize_insight[R : @policy.UiSessionRepository](
  repository : R,
  input : HypothesizeInsightInput,
  in_flight : Array[@command.CommandInteraction]
) -> Result[@command.CommandInteraction, UsecaseError] {
  match require_authenticated_session(repository, input.sessionIdentifier) {
    Err(e) => Err(e)
    Ok(session) => {
      let intent = @policy.create(
        @session.CommandType::Hypothesize,
        Some({ targetIdentifier: input.insightIdentifier, targetType: "insight" }),
      )
      if not(@policy.is_satisfied_by(session, intent)) {
        Err(
          UsecaseError::OperationBlocked(
            "Hypothesize insight is blocked by permission policy",
          ),
        )
      } else {
        let interaction : @command.CommandInteraction = {
          identifier: input.submissionIdentifier,
          submissionIdentifier: input.submissionIdentifier,
          trace: input.trace,
          commandType: @session.CommandType::Hypothesize,
          target: Some({
            targetIdentifier: input.insightIdentifier,
            targetType: "insight",
          }),
          status: @command.CommandStatus::Draft,
          responseCode: None,
          reasonCode: None,
          actionReasonCode: None,
        }
        submit_interaction(interaction, in_flight)
      }
    }
  }
}

// ============================================================================
// HypothesisWorkflowService — SCR-007 promote / adopt hypothesis
// ============================================================================

/// Input for promoting a hypothesis to live.
pub(all) struct PromoteHypothesisInput {
  sessionIdentifier : String
  submissionIdentifier : String
  trace : String
  hypothesisIdentifier : String
  updatedAt : String
} derive(Show)

/// Input for adopting a hypothesis strategy.
pub(all) struct AdoptHypothesisInput {
  sessionIdentifier : String
  submissionIdentifier : String
  trace : String
  hypothesisIdentifier : String
  updatedAt : String
} derive(Show)

/// Validate and prepare a promote-hypothesis command interaction.
/// RULE-FE-001: session must be Authenticated.
pub fn promote_hypothesis[R : @policy.UiSessionRepository](
  repository : R,
  input : PromoteHypothesisInput,
  in_flight : Array[@command.CommandInteraction]
) -> Result[@command.CommandInteraction, UsecaseError] {
  match require_authenticated_session(repository, input.sessionIdentifier) {
    Err(e) => Err(e)
    Ok(session) => {
      let intent = @policy.create(
        @session.CommandType::Promote,
        Some({
          targetIdentifier: input.hypothesisIdentifier,
          targetType: "hypothesis",
        }),
      )
      if not(@policy.is_satisfied_by(session, intent)) {
        Err(
          UsecaseError::OperationBlocked(
            "Promote hypothesis is blocked by permission policy",
          ),
        )
      } else {
        let interaction : @command.CommandInteraction = {
          identifier: input.submissionIdentifier,
          submissionIdentifier: input.submissionIdentifier,
          trace: input.trace,
          commandType: @session.CommandType::Promote,
          target: Some({
            targetIdentifier: input.hypothesisIdentifier,
            targetType: "hypothesis",
          }),
          status: @command.CommandStatus::Draft,
          responseCode: None,
          reasonCode: None,
          actionReasonCode: None,
        }
        submit_interaction(interaction, in_flight)
      }
    }
  }
}

/// Validate and prepare an adopt-hypothesis command interaction.
pub fn adopt_hypothesis[R : @policy.UiSessionRepository](
  repository : R,
  input : AdoptHypothesisInput,
  in_flight : Array[@command.CommandInteraction]
) -> Result[@command.CommandInteraction, UsecaseError] {
  match require_authenticated_session(repository, input.sessionIdentifier) {
    Err(e) => Err(e)
    Ok(session) => {
      let intent = @policy.create(
        @session.CommandType::Adopt,
        Some({
          targetIdentifier: input.hypothesisIdentifier,
          targetType: "hypothesis",
        }),
      )
      if not(@policy.is_satisfied_by(session, intent)) {
        Err(
          UsecaseError::OperationBlocked(
            "Adopt hypothesis is blocked by permission policy",
          ),
        )
      } else {
        let interaction : @command.CommandInteraction = {
          identifier: input.submissionIdentifier,
          submissionIdentifier: input.submissionIdentifier,
          trace: input.trace,
          commandType: @session.CommandType::Adopt,
          target: Some({
            targetIdentifier: input.hypothesisIdentifier,
            targetType: "hypothesis",
          }),
          status: @command.CommandStatus::Draft,
          responseCode: None,
          reasonCode: None,
          actionReasonCode: None,
        }
        submit_interaction(interaction, in_flight)
      }
    }
  }
}

// ============================================================================
// DashboardCommandService — SCR-001 run-cycle command
// ============================================================================

/// Input for issuing a manual run-cycle command from the dashboard.
pub(all) struct RunCycleInput {
  sessionIdentifier : String
  submissionIdentifier : String
  trace : String
  updatedAt : String
} derive(Show)

/// Validate and prepare a run-cycle command interaction.
/// RULE-FE-001: session must be Authenticated.
pub fn run_cycle[R : @policy.UiSessionRepository](
  repository : R,
  input : RunCycleInput,
  in_flight : Array[@command.CommandInteraction]
) -> Result[@command.CommandInteraction, UsecaseError] {
  match require_authenticated_session(repository, input.sessionIdentifier) {
    Err(e) => Err(e)
    Ok(session) => {
      let intent = @policy.create(@session.CommandType::RunCycle, None)
      if not(@policy.is_satisfied_by(session, intent)) {
        Err(UsecaseError::OperationBlocked("RunCycle is blocked by permission policy"))
      } else {
        let interaction : @command.CommandInteraction = {
          identifier: input.submissionIdentifier,
          submissionIdentifier: input.submissionIdentifier,
          trace: input.trace,
          commandType: @session.CommandType::RunCycle,
          target: None,
          status: @command.CommandStatus::Draft,
          responseCode: None,
          reasonCode: None,
          actionReasonCode: None,
        }
        submit_interaction(interaction, in_flight)
      }
    }
  }
}

// ============================================================================
// CommandResponseService — complete a submitted CommandInteraction
// ============================================================================

/// Acknowledge a submitted command with a successful BFF response.
/// Transitions Submitting → Accepted.
pub fn acknowledge_command(
  interaction : @command.CommandInteraction,
  response_code : Int
) -> Result[@command.CommandInteraction, UsecaseError] {
  match @command.acknowledge(interaction, response_code) {
    Ok(completed_interaction) => Ok(completed_interaction)
    Err(domain_error) => Err(UsecaseError::DomainViolation(domain_error))
  }
}

/// Reject a submitted command with an error BFF response.
/// Transitions Submitting → Rejected.
pub fn reject_submitted_command(
  interaction : @command.CommandInteraction,
  response_code : Int,
  reason_code : @command.ReasonCode
) -> Result[@command.CommandInteraction, UsecaseError] {
  match @command.reject_command(interaction, response_code, reason_code) {
    Ok(completed_interaction) => Ok(completed_interaction)
    Err(domain_error) => Err(UsecaseError::DomainViolation(domain_error))
  }
}

// ============================================================================
// Private helpers
// ============================================================================

/// Require an Authenticated session or return Unauthorized.
fn require_authenticated_session[R : @policy.UiSessionRepository](
  repository : R,
  session_identifier : String
) -> Result[@session.UiSession, UsecaseError] {
  match repository.find(session_identifier) {
    None => Err(UsecaseError::Unauthorized("Session not found"))
    Some(s) =>
      if s.authState == @session.AuthState::Authenticated {
        Ok(s)
      } else {
        Err(UsecaseError::Unauthorized("Session is not authenticated"))
      }
  }
}

/// Submit a draft interaction to the domain submit_command function.
fn submit_interaction(
  interaction : @command.CommandInteraction,
  in_flight : Array[@command.CommandInteraction]
) -> Result[@command.CommandInteraction, UsecaseError] {
  match @command.submit_command(interaction, in_flight) {
    Ok(submitting_interaction) => Ok(submitting_interaction)
    Err(@session.DomainError::DuplicateSubmission(msg)) =>
      Err(UsecaseError::DuplicateSubmission(msg))
    Err(domain_error) => Err(UsecaseError::DomainViolation(domain_error))
  }
}

/// Create a new UiSession in Unauthenticated state via domain factory.
fn new_session(identifier : String, updated_at : String) -> @session.UiSession {
  @session.new_session(identifier, updated_at)
}

/// Create a new ReadModelProjection in Initial state via domain factory.
fn new_projection(
  screen : @projection.ProjectionScreen,
  updated_at : String
) -> @projection.ReadModelProjection {
  @projection.new_projection("proj", screen, updated_at)
}
