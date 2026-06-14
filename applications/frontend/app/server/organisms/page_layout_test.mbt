///| Tests for the PageLayout organism (header + sidebar + main shell).

///|
test "page_layout renders the header, sidebar and a main region" {
  let html = @server_dom.render(
    page_layout(
      current_path="/dashboard",
      body=[@server_dom.text("本文")],
    ),
  )
  assert_true(html.contains("<header"))
  assert_true(html.contains("<aside"))
  assert_true(html.contains("<main"))
  assert_true(html.contains("role=\"main\""))
  assert_true(html.contains("本文"))
}

///|
test "page_layout offsets main by the header height and sidebar width" {
  let html = @server_dom.render(
    page_layout(current_path="/dashboard", body=[@server_dom.text("x")]),
  )
  // The main region must be pushed below/right of the fixed chrome so content
  // is never hidden behind it.
  assert_true(html.contains("margin-top:var(--header-height"))
  assert_true(html.contains("margin-left:var(--sidebar-width"))
}

///|
test "page_layout renders an h1 page title when provided" {
  let html = @server_dom.render(
    page_layout(
      current_path="/orders",
      page_title="注文管理",
      body=[@server_dom.text("x")],
    ),
  )
  assert_true(html.contains("<h1"))
  assert_true(html.contains("注文管理"))
}

///|
test "page_layout omits the h1 when no title is given" {
  let html = @server_dom.render(
    page_layout(current_path="/orders", body=[@server_dom.text("x")]),
  )
  assert_false(html.contains("<h1"))
}

///|
test "page_layout highlights the active nav item from current_path" {
  let html = @server_dom.render(
    page_layout(current_path="/audit", body=[@server_dom.text("x")]),
  )
  assert_true(html.contains("aria-current=\"page\""))
  assert_true(html.contains("href=\"/audit\""))
}

///|
test "page_layout forwards the user identity to the header" {
  let html = @server_dom.render(
    page_layout(
      current_path="/dashboard",
      body=[@server_dom.text("x")],
      user_name="運用者",
      user_role="admin",
    ),
  )
  assert_true(html.contains("運用者"))
  assert_true(html.contains("admin"))
}

///|
test "page_layout renders multiple body nodes in order" {
  let html = @server_dom.render(
    page_layout(
      current_path="/dashboard",
      body=[@server_dom.text("最初の本文"), @server_dom.text("次の本文")],
    ),
  )
  assert_true(html.contains("最初の本文"))
  assert_true(html.contains("次の本文"))
  // The two nodes appear in body order: everything up to the first marker must
  // not yet contain the second one.
  let before_second = html.split("次の本文").to_array()[0]
  assert_true(before_second.contains("最初の本文"))
}
