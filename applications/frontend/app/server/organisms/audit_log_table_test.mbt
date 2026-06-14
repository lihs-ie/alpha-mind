///| Tests for the AuditLogTable organism.

///|
fn sample_audit(result : String) -> AuditRow {
  {
    identifier: "01AUDIT",
    occurred_at: "2026-06-15T00:00:00Z",
    event_type: "order.approved",
    service: "svc-execution",
    result,
    trace: "01TRACE",
  }
}

///|
test "audit_log_table renders an ARIA table with audit columns" {
  let html = @server_dom.render(audit_log_table([sample_audit("EXECUTED")]))
  assert_true(html.contains("role=\"table\""))
  assert_true(html.contains("監査ログ一覧"))
  assert_true(html.contains("発生時刻"))
  assert_true(html.contains("トレース"))
}

///|
test "audit_log_table renders a result status badge" {
  let html = @server_dom.render(audit_log_table([sample_audit("EXECUTED")]))
  assert_true(html.contains("執行済み"))
}

///|
test "audit_log_table renders the event type and service" {
  let html = @server_dom.render(audit_log_table([sample_audit("EXECUTED")]))
  assert_true(html.contains("order.approved"))
  assert_true(html.contains("svc-execution"))
}

///|
test "audit trace is a copyable chip carrying the trace id" {
  let html = @server_dom.render(audit_log_table([sample_audit("EXECUTED")]))
  assert_true(html.contains("01TRACE"))
  assert_true(html.contains("data-copy=\"trace\""))
  assert_true(html.contains("data-trace=\"01TRACE\""))
  assert_true(html.contains("トレースをコピー"))
}

///|
test "audit timestamps and trace use the monospace face" {
  let html = @server_dom.render(audit_log_table([sample_audit("EXECUTED")]))
  assert_true(html.contains("JetBrains Mono"))
}

///|
test "audit_log_table renders the empty state when there are no logs" {
  let html = @server_dom.render(audit_log_table([], empty_message="ログなし"))
  assert_true(html.contains("ログなし"))
}

///|
test "audit rows carry the audit id as a data attribute" {
  let html = @server_dom.render(audit_log_table([sample_audit("EXECUTED")]))
  assert_true(html.contains("data-audit-id=\"01AUDIT\""))
}
