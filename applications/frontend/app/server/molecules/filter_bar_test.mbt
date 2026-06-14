///| Tests for the filter_bar molecule.

///|
test "filter_bar renders a labelled search landmark with an apply button" {
  let html = @server_dom.render(filter_bar("orders"))
  assert_true(html.contains("role=\"search\""))
  assert_true(html.contains("aria-label=\"一覧フィルタ\""))
  assert_true(html.contains("フィルタ適用"))
}

///|
test "filter_bar renders status chips from the provided options" {
  let html = @server_dom.render(
    filter_bar("orders", status_options=[
      { status: "PROPOSED", selected: true },
      { status: "APPROVED", selected: false },
    ]),
  )
  // status_badge maps PROPOSED -> 提案中, APPROVED -> 承認済み
  assert_true(html.contains("提案中"))
  assert_true(html.contains("承認済み"))
  assert_true(html.contains("data-status=\"PROPOSED\""))
}

///|
test "filter_bar marks the selected chip as checked" {
  let html = @server_dom.render(
    filter_bar("orders", status_options=[{ status: "FAILED", selected: true }]),
  )
  assert_true(html.contains("aria-checked=\"true\""))
}

///|
test "filter_bar marks an unselected chip as unchecked" {
  let html = @server_dom.render(
    filter_bar("orders", status_options=[{ status: "FAILED", selected: false }]),
  )
  assert_true(html.contains("aria-checked=\"false\""))
}

///|
test "filter_bar renders a from/to date range when requested" {
  let html = @server_dom.render(filter_bar("audit", show_date_range=true))
  assert_true(html.contains("id=\"audit-from\""))
  assert_true(html.contains("id=\"audit-to\""))
  assert_true(html.contains("開始日時"))
  assert_true(html.contains("終了日時"))
}

///|
test "filter_bar seeds the date inputs with provided values" {
  let html = @server_dom.render(
    filter_bar(
      "audit",
      show_date_range=true,
      from_value="2026-06-01",
      to_value="2026-06-15",
    ),
  )
  assert_true(html.contains("2026-06-01"))
  assert_true(html.contains("2026-06-15"))
}
