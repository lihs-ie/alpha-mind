///| Tests for the OrderTable organism.

///|
fn sample_order(status : String) -> OrderRow {
  {
    identifier: "01ORDER",
    symbol: "7203",
    side: "BUY",
    qty: "100",
    status,
    created_at: "2026-06-15T00:00:00Z",
  }
}

///|
test "order_table renders an ARIA table with order columns" {
  let html = @server_dom.render(order_table([sample_order("PROPOSED")]))
  assert_true(html.contains("role=\"table\""))
  assert_true(html.contains("注文候補一覧"))
  assert_true(html.contains("注文ID"))
  assert_true(html.contains("操作"))
}

///|
test "order_table renders a status badge per row" {
  let html = @server_dom.render(order_table([sample_order("EXECUTED")]))
  // status_badge_atom maps EXECUTED → 執行済み.
  assert_true(html.contains("執行済み"))
}

///|
test "order_table identifiers and quantities use the monospace face" {
  let html = @server_dom.render(order_table([sample_order("PROPOSED")]))
  assert_true(html.contains("01ORDER"))
  assert_true(html.contains("JetBrains Mono"))
}

///|
test "PROPOSED orders offer approve and reject actions" {
  let html = @server_dom.render(order_table([sample_order("PROPOSED")]))
  assert_true(html.contains("承認"))
  assert_true(html.contains("却下"))
  assert_true(html.contains("data-action=\"approve\""))
  assert_true(html.contains("data-action=\"reject\""))
}

///|
test "approval is disabled while the kill switch is enabled" {
  let html = @server_dom.render(
    order_table([sample_order("PROPOSED")], kill_switch_enabled=true),
  )
  // The approve button is disabled (cursor:not-allowed) but reject stays.
  assert_true(html.contains("cursor:not-allowed"))
  assert_true(html.contains("却下"))
}

///|
test "FAILED orders offer a retry action" {
  let html = @server_dom.render(order_table([sample_order("FAILED")]))
  assert_true(html.contains("再送"))
  assert_true(html.contains("data-action=\"retry\""))
}

///|
test "terminal orders offer no row actions" {
  let html = @server_dom.render(order_table([sample_order("REJECTED")]))
  assert_false(html.contains("data-action=\"approve\""))
  assert_false(html.contains("data-action=\"retry\""))
}

///|
test "order_table renders the empty state when there are no orders" {
  let html = @server_dom.render(order_table([], empty_message="注文なし"))
  assert_true(html.contains("注文なし"))
}

///|
test "order rows carry the order id as a data attribute for the Island" {
  let html = @server_dom.render(order_table([sample_order("PROPOSED")]))
  assert_true(html.contains("data-order-id=\"01ORDER\""))
}
