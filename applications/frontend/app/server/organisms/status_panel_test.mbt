///| Tests for the StatusPanel organism (operations panel).

///|
test "status_panel renders the runtime and kill-switch status badges" {
  let html = @server_dom.render(
    status_panel(runtime_state="RUNNING", kill_switch_enabled=false),
  )
  // status_badge_atom: RUNNING → 稼働中, DISABLED → 無効.
  assert_true(html.contains("稼働中"))
  assert_true(html.contains("無効"))
  assert_true(html.contains("運用状態"))
  assert_true(html.contains("Kill Switch"))
}

///|
test "a running panel offers the stop action" {
  let html = @server_dom.render(
    status_panel(runtime_state="RUNNING", kill_switch_enabled=false),
  )
  assert_true(html.contains("運用停止"))
  assert_true(html.contains("data-action=\"toggle-runtime\""))
}

///|
test "a stopped panel offers the start action" {
  let html = @server_dom.render(
    status_panel(runtime_state="STOPPED", kill_switch_enabled=false),
  )
  assert_true(html.contains("運用開始"))
}

///|
test "status_panel renders the kill-switch toggle control" {
  let html = @server_dom.render(
    status_panel(runtime_state="STOPPED", kill_switch_enabled=false),
  )
  assert_true(html.contains("role=\"switch\""))
  assert_true(html.contains("data-action=\"toggle-kill-switch\""))
}

///|
test "an enabled kill switch shows a warning and reports ON state" {
  let html = @server_dom.render(
    status_panel(runtime_state="STOPPED", kill_switch_enabled=true),
  )
  assert_true(html.contains("role=\"alert\""))
  assert_true(html.contains("kill switch が有効です"))
  assert_true(html.contains("有効"))
  assert_true(html.contains("aria-checked=\"true\""))
}

///|
test "a disabled kill switch shows no warning" {
  let html = @server_dom.render(
    status_panel(runtime_state="RUNNING", kill_switch_enabled=false),
  )
  assert_false(html.contains("kill switch が有効です"))
}

///|
test "status_panel uses a card surface and a custom title" {
  let html = @server_dom.render(
    status_panel(
      runtime_state="RUNNING",
      kill_switch_enabled=false,
      title="操作",
    ),
  )
  assert_true(html.contains("--color-surface"))
  assert_true(html.contains("操作"))
}
