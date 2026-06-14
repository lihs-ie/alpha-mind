///| Tests for the AppHeader organism.
///| Renders to HTML via @server_dom.render and asserts on the fixed-chrome
///| structure, layout tokens and the optional user / clock areas.

///|
test "app_header renders a banner header with the app name" {
  let html = @server_dom.render(app_header())
  assert_true(html.contains("<header"))
  assert_true(html.contains("role=\"banner\""))
  assert_true(html.contains("alpha-mind"))
}

///|
test "app_header is fixed and uses the --header-height layout token" {
  let html = @server_dom.render(app_header())
  assert_true(html.contains("position:fixed"))
  assert_true(html.contains("--header-height"))
}

///|
test "app_header sits at the sticky z-layer" {
  let html = @server_dom.render(app_header())
  assert_true(html.contains("--z-sticky"))
}

///|
test "app_header without a user omits the user menu" {
  let html = @server_dom.render(app_header())
  assert_false(html.contains("ユーザーメニュー"))
}

///|
test "app_header renders the user name and role badge" {
  let html = @server_dom.render(
    app_header(user_name="運用者", user_role="admin"),
  )
  assert_true(html.contains("運用者"))
  assert_true(html.contains("admin"))
  assert_true(html.contains("ユーザーメニュー"))
}

///|
test "app_header renders the clock slot in the monospace face" {
  let html = @server_dom.render(app_header(current_time="2026-06-15 09:00"))
  assert_true(html.contains("2026-06-15 09:00"))
  assert_true(html.contains("JetBrains Mono"))
  assert_true(html.contains("data-role=\"clock\""))
}

///|
test "app_header allows overriding the app name" {
  let html = @server_dom.render(app_header(app_name="テスト"))
  assert_true(html.contains("テスト"))
}
