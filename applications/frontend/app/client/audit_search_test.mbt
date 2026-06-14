///| Tests for the AuditSearch Island logic (SCR-004).
///| Verifies Props serialization, search-condition validation (期間 / trace ULID),
///| and the ULID format check.

///|
test "AuditRowProps round-trip ToJson/FromJson" {
  let row : AuditRowProps = {
    identifier: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
    occurred_at: "2026-01-15T09:00:00Z",
    event_type: "order.approved",
    service: "svc-bff",
    result: "success",
    trace: "01ARZ3NDEKTSV4RRFFQ69G5FAW",
  }
  let json = row.to_json()
  let restored : AuditRowProps = @json.from_json(json)
  assert_eq(row.identifier, restored.identifier)
  assert_eq(row.occurred_at, restored.occurred_at)
  assert_eq(row.event_type, restored.event_type)
  assert_eq(row.service, restored.service)
  assert_eq(row.result, restored.result)
  assert_eq(row.trace, restored.trace)
}

///|
test "AuditSearchProps round-trip with multiple logs" {
  let props : AuditSearchProps = {
    bff_base_url: "https://api.alpha-mind.dev",
    initial_logs: [
      {
        identifier: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
        occurred_at: "2026-01-15T09:00:00Z",
        event_type: "order.approved",
        service: "svc-bff",
        result: "success",
        trace: "01ARZ3NDEKTSV4RRFFQ69G5FAW",
      },
      {
        identifier: "01BRZ3NDEKTSV4RRFFQ69G5FAX",
        occurred_at: "2026-01-15T10:00:00Z",
        event_type: "order.failed",
        service: "svc-execution",
        result: "failed",
        trace: "01BRZ3NDEKTSV4RRFFQ69G5FAY",
      },
    ],
  }
  let json = props.to_json()
  let restored : AuditSearchProps = @json.from_json(json)
  assert_eq(props.bff_base_url, restored.bff_base_url)
  assert_eq(restored.initial_logs.length(), 2)
  assert_eq(restored.initial_logs[0].result, "success")
  assert_eq(restored.initial_logs[1].result, "failed")
  assert_eq(restored.initial_logs[1].service, "svc-execution")
}

///|
test "AuditSearchProps round-trip with empty logs" {
  let props : AuditSearchProps = {
    bff_base_url: "http://localhost:8080",
    initial_logs: [],
  }
  let json = props.to_json()
  let restored : AuditSearchProps = @json.from_json(json)
  assert_eq(restored.bff_base_url, "http://localhost:8080")
  assert_eq(restored.initial_logs.length(), 0)
}

// ── ULID format validation (SCR-004 §5) ──────────────────────────────────────

///|
test "is_valid_ulid — canonical 26-char Crockford base32 is valid" {
  assert_eq(is_valid_ulid("01ARZ3NDEKTSV4RRFFQ69G5FAV"), true)
}

///|
test "is_valid_ulid — wrong length is invalid" {
  assert_eq(is_valid_ulid("01ARZ3NDEKTSV4RRFFQ69G5FA"), false) // 25 chars
  assert_eq(is_valid_ulid("01ARZ3NDEKTSV4RRFFQ69G5FAVX"), false) // 27 chars
  assert_eq(is_valid_ulid(""), false)
}

///|
test "is_valid_ulid — forbidden Crockford letters I/L/O/U are invalid" {
  assert_eq(is_valid_ulid("01ARZ3NDEKTSV4RRFFQ69G5FAI"), false)
  assert_eq(is_valid_ulid("01ARZ3NDEKTSV4RRFFQ69G5FAL"), false)
  assert_eq(is_valid_ulid("01ARZ3NDEKTSV4RRFFQ69G5FAO"), false)
  assert_eq(is_valid_ulid("01ARZ3NDEKTSV4RRFFQ69G5FAU"), false)
}

// ── Search-condition validation (SCR-004 §5) ─────────────────────────────────

///|
test "validate_audit_search — all empty (unbounded) is valid" {
  assert_eq(validate_audit_search("", "", ""), "")
}

///|
test "validate_audit_search — From <= To is valid" {
  assert_eq(
    validate_audit_search(
      "2026-01-15T09:00", "2026-01-15T10:00", "",
    ),
    "",
  )
}

///|
test "validate_audit_search — From == To is valid" {
  assert_eq(
    validate_audit_search(
      "2026-01-15T09:00", "2026-01-15T09:00", "",
    ),
    "",
  )
}

///|
test "validate_audit_search — From > To is rejected" {
  assert_eq(
    validate_audit_search(
      "2026-01-15T11:00", "2026-01-15T09:00", "",
    ),
    "期間の指定が不正です",
  )
}

///|
test "validate_audit_search — only From given (To empty) is valid" {
  assert_eq(validate_audit_search("2026-01-15T09:00", "", ""), "")
}

///|
test "validate_audit_search — only To given (From empty) is valid" {
  assert_eq(validate_audit_search("", "2026-01-15T09:00", ""), "")
}

///|
test "validate_audit_search — valid trace ULID passes" {
  assert_eq(
    validate_audit_search("", "", "01ARZ3NDEKTSV4RRFFQ69G5FAV"),
    "",
  )
}

///|
test "validate_audit_search — invalid trace format is rejected" {
  assert_eq(
    validate_audit_search("", "", "not-a-ulid"),
    "trace形式が不正です",
  )
}

///|
test "validate_audit_search — empty trace (未指定) is allowed" {
  assert_eq(validate_audit_search("", "", ""), "")
}

///|
test "validate_audit_search — period error takes precedence over trace error" {
  assert_eq(
    validate_audit_search(
      "2026-01-15T11:00", "2026-01-15T09:00", "bad-trace",
    ),
    "期間の指定が不正です",
  )
}
