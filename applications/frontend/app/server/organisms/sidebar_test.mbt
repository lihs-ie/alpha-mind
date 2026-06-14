///| Tests for the Sidebar organism + the shared navigation model.

///|
test "primary_nav_items lists the authenticated screens in menu order" {
  let items = primary_nav_items()
  assert_eq(items.length(), 7)
  assert_eq(items[0].path, "/dashboard")
  assert_eq(items[1].path, "/settings/strategy")
  assert_eq(items[2].path, "/orders")
  assert_eq(items[3].path, "/audit")
  assert_eq(items[4].path, "/models/validation")
}

///|
test "sidebar renders an aside with a labelled navigation" {
  let html = @server_dom.render(sidebar(current_path="/dashboard"))
  assert_true(html.contains("<aside"))
  assert_true(html.contains("メインナビゲーション"))
  assert_true(html.contains("<nav"))
}

///|
test "sidebar is fixed and uses the --sidebar-width / --header-height tokens" {
  let html = @server_dom.render(sidebar(current_path="/dashboard"))
  assert_true(html.contains("position:fixed"))
  assert_true(html.contains("--sidebar-width"))
  assert_true(html.contains("--header-height"))
}

///|
test "sidebar sits at the sticky z-layer" {
  let html = @server_dom.render(sidebar(current_path="/orders"))
  assert_true(html.contains("--z-sticky"))
}

///|
test "sidebar renders every primary nav label as a link" {
  let html = @server_dom.render(sidebar(current_path="/dashboard"))
  assert_true(html.contains("ダッシュボード"))
  assert_true(html.contains("注文管理"))
  assert_true(html.contains("監査ログ"))
  assert_true(html.contains("href=\"/orders\""))
}

///|
test "sidebar marks the current path active with aria-current" {
  let html = @server_dom.render(sidebar(current_path="/orders"))
  assert_true(html.contains("aria-current=\"page\""))
  assert_true(html.contains("data-active=\"true\""))
}

///|
test "sidebar does not mark a non-current path active" {
  let html = @server_dom.render(
    sidebar(current_path="/dashboard", items=[{ label: "注文管理", path: "/orders" }]),
  )
  assert_false(html.contains("aria-current=\"page\""))
  assert_true(html.contains("data-active=\"false\""))
}

///|
test "sidebar accepts a custom nav item list" {
  let html = @server_dom.render(
    sidebar(
      current_path="/x",
      items=[{ label: "カスタム", path: "/x" }],
    ),
  )
  assert_true(html.contains("カスタム"))
  assert_true(html.contains("href=\"/x\""))
}
