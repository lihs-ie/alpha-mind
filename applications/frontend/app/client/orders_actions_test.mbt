///| Tests for the OrdersActions Island logic (SCR-003).
///| Verifies Props serialization, status → action-visibility mapping (state machine),
///| reject validation, and kill-switch-disables-approve behaviour.

///|
test "OrderRowProps round-trip ToJson/FromJson" {
  let row : OrderRowProps = {
    identifier: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
    symbol: "7203.T",
    side: "BUY",
    qty: 100.0,
    status: "PROPOSED",
    created_at: "2026-01-15T09:00:00Z",
  }
  let json = row.to_json()
  let restored : OrderRowProps = @json.from_json(json)
  assert_eq(row.identifier, restored.identifier)
  assert_eq(row.symbol, restored.symbol)
  assert_eq(row.side, restored.side)
  assert_eq(row.qty, restored.qty)
  assert_eq(row.status, restored.status)
  assert_eq(row.created_at, restored.created_at)
}

///|
test "OrdersActionsProps round-trip with multiple orders" {
  let props : OrdersActionsProps = {
    bff_base_url: "https://api.alpha-mind.dev",
    initial_kill_switch_enabled: false,
    initial_orders: [
      {
        identifier: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
        symbol: "AAPL",
        side: "BUY",
        qty: 1.0,
        status: "PROPOSED",
        created_at: "2026-01-15T09:00:00Z",
      },
      {
        identifier: "01BRZ3NDEKTSV4RRFFQ69G5FAW",
        symbol: "9984.T",
        side: "SELL",
        qty: 50.0,
        status: "FAILED",
        created_at: "2026-01-15T10:00:00Z",
      },
    ],
  }
  let json = props.to_json()
  let restored : OrdersActionsProps = @json.from_json(json)
  assert_eq(props.bff_base_url, restored.bff_base_url)
  assert_eq(props.initial_kill_switch_enabled, restored.initial_kill_switch_enabled)
  assert_eq(restored.initial_orders.length(), 2)
  assert_eq(restored.initial_orders[0].status, "PROPOSED")
  assert_eq(restored.initial_orders[1].status, "FAILED")
}

///|
test "OrdersActionsProps round-trip preserves kill switch enabled" {
  let props : OrdersActionsProps = {
    bff_base_url: "http://localhost:8080",
    initial_kill_switch_enabled: true,
    initial_orders: [],
  }
  let json = props.to_json()
  let restored : OrdersActionsProps = @json.from_json(json)
  assert_eq(restored.initial_kill_switch_enabled, true)
  assert_eq(restored.initial_orders.length(), 0)
}

// ── State machine: approve permitted only from PROPOSED, blocked by kill switch ──

///|
test "can_approve — PROPOSED with kill switch disabled is allowed" {
  assert_eq(can_approve("PROPOSED", false), true)
}

///|
test "can_approve — PROPOSED with kill switch enabled is blocked" {
  assert_eq(can_approve("PROPOSED", true), false)
}

///|
test "can_approve — non-PROPOSED statuses are never approvable" {
  assert_eq(can_approve("APPROVED", false), false)
  assert_eq(can_approve("EXECUTED", false), false)
  assert_eq(can_approve("REJECTED", false), false)
  assert_eq(can_approve("FAILED", false), false)
}

// ── State machine: reject permitted only from PROPOSED ──

///|
test "can_reject — only PROPOSED is rejectable" {
  assert_eq(can_reject("PROPOSED"), true)
  assert_eq(can_reject("APPROVED"), false)
  assert_eq(can_reject("EXECUTED"), false)
  assert_eq(can_reject("REJECTED"), false)
  assert_eq(can_reject("FAILED"), false)
}

// ── State machine: retry permitted only from FAILED ──

///|
test "can_retry — only FAILED is retryable" {
  assert_eq(can_retry("FAILED"), true)
  assert_eq(can_retry("PROPOSED"), false)
  assert_eq(can_retry("APPROVED"), false)
  assert_eq(can_retry("EXECUTED"), false)
  assert_eq(can_retry("REJECTED"), false)
}

// ── Terminal / in-flight statuses expose no mutating action ──

///|
test "EXECUTED / REJECTED / APPROVED expose no enabled mutating action" {
  for status in ["EXECUTED", "REJECTED", "APPROVED"] {
    assert_eq(can_approve(status, false), false)
    assert_eq(can_reject(status), false)
    assert_eq(can_retry(status), false)
  }
}

// ── Reject validation (SCR-003 §5) ──

///|
test "validate_reject — empty reason code is rejected" {
  assert_eq(validate_reject("", ""), "却下理由コードを選択してください")
}

///|
test "validate_reject — reason code present, short comment is valid" {
  assert_eq(validate_reject("MANUAL_OPERATION", "妥当なコメント"), "")
}

///|
test "validate_reject — comment over 120 chars is rejected" {
  let long_comment = "あ".repeat(121)
  assert_eq(
    validate_reject("RISK_REJECTION", long_comment),
    "コメントは120文字以内で入力してください",
  )
}

///|
test "validate_reject — comment of exactly 120 chars is valid" {
  let comment = "x".repeat(120)
  assert_eq(validate_reject("MANUAL_OPERATION", comment), "")
}
