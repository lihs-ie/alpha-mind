///| Infrastructure layer — concrete implementations of domain repository ports.
///|
///| This package provides:
///|   - InMemorySessionRepository: in-memory implementation of UiSessionRepository
///|   - InMemoryProjectionRepository: in-memory implementation of ProjectionRepository
///|   - JwtTokenStore: JWT access token storage and expiry management
///|   - ProblemDetail: RFC 9457 Problem Detail parser for BFF error responses
///|
///| No BFF HTTP adapter lives here — that is #74 (acl layer).
///| All types are pure in-memory / client-side state; no IO primitives are used.

// ============================================================================
// InMemorySessionRepository
// ============================================================================

/// In-memory implementation of the UiSessionRepository port.
/// Stores a single UiSession keyed by identifier (string map simulation via
/// a mutable slot — sufficient for the single-user MVP).
pub struct InMemorySessionRepository {
  mut entries : Array[SessionEntry]
}

struct SessionEntry {
  identifier : String
  session : @session.UiSession
}

/// Factory: create an empty InMemorySessionRepository.
pub fn InMemorySessionRepository::new() -> InMemorySessionRepository {
  { entries: [] }
}

/// Find a UiSession by identifier. Returns None if not found.
pub fn InMemorySessionRepository::find(
  self : InMemorySessionRepository,
  identifier : String
) -> @session.UiSession? {
  let mut result : @session.UiSession? = None
  for entry in self.entries {
    if entry.identifier == identifier {
      result = Some(entry.session)
    }
  }
  result
}

/// Persist (upsert) a UiSession into the repository.
pub fn InMemorySessionRepository::persist(
  self : InMemorySessionRepository,
  session : @session.UiSession
) -> Unit {
  let mut found = false
  let updated_entries : Array[SessionEntry] = []
  for entry in self.entries {
    if entry.identifier == session.identifier {
      updated_entries.push({ identifier: session.identifier, session })
      found = true
    } else {
      updated_entries.push(entry)
    }
  }
  if not(found) {
    updated_entries.push({ identifier: session.identifier, session })
  }
  self.entries = updated_entries
}

/// Remove the UiSession with the given identifier from the repository.
pub fn InMemorySessionRepository::terminate(
  self : InMemorySessionRepository,
  identifier : String
) -> Unit {
  let remaining : Array[SessionEntry] = []
  for entry in self.entries {
    if entry.identifier != identifier {
      remaining.push(entry)
    }
  }
  self.entries = remaining
}

impl @policy.UiSessionRepository for InMemorySessionRepository with find(
  self,
  identifier
) {
  self.find(identifier)
}

impl @policy.UiSessionRepository for InMemorySessionRepository with persist(
  self,
  session
) {
  self.persist(session)
}

impl @policy.UiSessionRepository for InMemorySessionRepository with terminate(
  self,
  identifier
) {
  self.terminate(identifier)
}

// ============================================================================
// InMemoryProjectionRepository
// ============================================================================

/// In-memory implementation of the ProjectionRepository port.
/// Stores one ReadModelProjection per ProjectionScreen.
pub struct InMemoryProjectionRepository {
  mut entries : Array[ProjectionEntry]
}

struct ProjectionEntry {
  screen : @projection.ProjectionScreen
  projection : @projection.ReadModelProjection
}

/// Factory: create an empty InMemoryProjectionRepository.
pub fn InMemoryProjectionRepository::new() -> InMemoryProjectionRepository {
  { entries: [] }
}

/// Find a ReadModelProjection by screen. Returns None if not found.
pub fn InMemoryProjectionRepository::find_by_screen(
  self : InMemoryProjectionRepository,
  screen : @projection.ProjectionScreen
) -> @projection.ReadModelProjection? {
  let mut result : @projection.ReadModelProjection? = None
  for entry in self.entries {
    if entry.screen == screen {
      result = Some(entry.projection)
    }
  }
  result
}

/// Persist (upsert) a ReadModelProjection into the repository (keyed by screen).
pub fn InMemoryProjectionRepository::persist(
  self : InMemoryProjectionRepository,
  projection : @projection.ReadModelProjection
) -> Unit {
  let mut found = false
  let updated_entries : Array[ProjectionEntry] = []
  for entry in self.entries {
    if entry.screen == projection.screen {
      updated_entries.push({ screen: projection.screen, projection })
      found = true
    } else {
      updated_entries.push(entry)
    }
  }
  if not(found) {
    updated_entries.push({ screen: projection.screen, projection })
  }
  self.entries = updated_entries
}

/// Remove the ReadModelProjection with the given identifier from the repository.
pub fn InMemoryProjectionRepository::terminate(
  self : InMemoryProjectionRepository,
  identifier : String
) -> Unit {
  let remaining : Array[ProjectionEntry] = []
  for entry in self.entries {
    if entry.projection.identifier != identifier {
      remaining.push(entry)
    }
  }
  self.entries = remaining
}

impl @policy.ProjectionRepository for InMemoryProjectionRepository with find_by_screen(
  self,
  screen
) {
  self.find_by_screen(screen)
}

impl @policy.ProjectionRepository for InMemoryProjectionRepository with persist(
  self,
  projection
) {
  self.persist(projection)
}

impl @policy.ProjectionRepository for InMemoryProjectionRepository with terminate(
  self,
  identifier
) {
  self.terminate(identifier)
}

// ============================================================================
// JwtTokenStore
// ============================================================================

/// Status of the stored JWT access token.
pub(all) enum TokenStatus {
  /// No token has been stored yet.
  Absent
  /// A valid (non-expired) token is present.
  Valid
  /// The stored token has expired.
  Expired
} derive(Eq, Show)

/// Holds an access token together with its expiry epoch (seconds since Unix epoch).
pub(all) struct TokenRecord {
  /// Raw JWT string.
  accessToken : String
  /// Expiry time in seconds since Unix epoch (from JWT `exp` claim).
  expiresAt : Int64
  /// User sub claim extracted from the JWT.
  subject : String
  /// Role extracted from the JWT claims.
  role : String
  /// Permission strings extracted from the JWT claims.
  permissions : Array[String]
} derive(Show)

/// Client-side JWT token store.
/// Holds the current access token in memory and provides expiry checks.
/// Token rotation (refresh) is not in scope for the MVP; the session expires and
/// the user must re-login.
pub struct JwtTokenStore {
  mut record : TokenRecord?
}

/// Factory: create an empty JwtTokenStore.
pub fn JwtTokenStore::new() -> JwtTokenStore {
  { record: None }
}

/// Store a new token record, replacing any previous token.
pub fn JwtTokenStore::store(
  self : JwtTokenStore,
  record : TokenRecord
) -> Unit {
  self.record = Some(record)
}

/// Clear the stored token (e.g., on explicit logout).
pub fn JwtTokenStore::clear(self : JwtTokenStore) -> Unit {
  self.record = None
}

/// Return the current token status given the current epoch time.
/// `now_epoch` should be the current time in seconds since Unix epoch.
pub fn JwtTokenStore::status(
  self : JwtTokenStore,
  now_epoch : Int64
) -> TokenStatus {
  match self.record {
    None => TokenStatus::Absent
    Some(r) =>
      if r.expiresAt > now_epoch {
        TokenStatus::Valid
      } else {
        TokenStatus::Expired
      }
  }
}

/// Return the raw access token string if the token is currently valid.
/// Returns None if absent or expired.
pub fn JwtTokenStore::access_token(
  self : JwtTokenStore,
  now_epoch : Int64
) -> String? {
  match self.record {
    None => None
    Some(r) =>
      if r.expiresAt > now_epoch {
        Some(r.accessToken)
      } else {
        None
      }
  }
}

/// Return the stored token record (regardless of expiry).
/// Useful for reading claims after expiry to display user info.
pub fn JwtTokenStore::record(self : JwtTokenStore) -> TokenRecord? {
  self.record
}

// ============================================================================
// ProblemDetail (RFC 9457)
// ============================================================================

/// Parsed representation of an RFC 9457 Problem Detail response from the BFF.
/// Maps `reasonCode` strings from the BFF API to the domain ReasonCode enum.
pub(all) struct ProblemDetail {
  /// HTTP status code.
  status : Int
  /// Human-readable title.
  title : String
  /// Human-readable detail message.
  detail : String
  /// Correlation identifier for cross-service tracing.
  trace : String?
  /// Mapped domain reason code.
  reasonCode : @command.ReasonCode
  /// Whether the caller should retry after a delay.
  retryable : Bool
} derive(Show)

/// Parse a `reasonCode` string from the BFF Problem Detail JSON into the domain enum.
/// Unknown codes fall back to `InternalError`.
pub fn parse_reason_code(raw : String) -> @command.ReasonCode {
  match raw {
    "AUTH_UNAUTHORIZED" | "AUTH_INVALID_CREDENTIALS" | "AUTH_TOKEN_EXPIRED"
    | "AUTH_FORBIDDEN" => @command.ReasonCode::AuthUnauthorized
    "OPERATION_NOT_ALLOWED" => @command.ReasonCode::OperationNotAllowed
    "DUPLICATE_COMMAND" => @command.ReasonCode::DuplicateCommand
    "REQUEST_VALIDATION_FAILED" => @command.ReasonCode::RequestValidationFailed
    "RESOURCE_NOT_FOUND" => @command.ReasonCode::ResourceNotFound
    "STATE_CONFLICT" => @command.ReasonCode::StateConflict
    "KILL_SWITCH_ENABLED" => @command.ReasonCode::KillSwitchEnabled
    _ => @command.ReasonCode::InternalError
  }
}

/// Construct a ProblemDetail from raw parsed fields.
/// Used by the ACL layer (#74) once it has decoded the JSON response body.
pub fn new_problem_detail(
  status : Int,
  title : String,
  detail : String,
  trace : String?,
  raw_reason_code : String,
  retryable : Bool
) -> ProblemDetail {
  {
    status,
    title,
    detail,
    trace,
    reasonCode: parse_reason_code(raw_reason_code),
    retryable,
  }
}

/// Determine whether a BFF HTTP status code should trigger an automatic retry.
/// 5xx errors are retryable; 4xx errors are not.
pub fn is_retryable_status(status : Int) -> Bool {
  status >= 500 && status < 600
}
