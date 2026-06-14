///| Tests for the button atom.
///| Renders the VNode to HTML via @server_dom.render and asserts on structure,
///| variants and states.

///|
test "button_atom renders a <button> with the label" {
  let html = @server_dom.render(button_atom("送信"))
  assert_true(html.contains("<button"))
  assert_true(html.contains("送信"))
  assert_true(html.contains("type=\"button\""))
}

///|
test "button_atom Primary variant uses the CTA accent colour" {
  let html = @server_dom.render(button_atom("OK", variant=Primary))
  assert_true(html.contains("--color-cta"))
}

///|
test "button_atom Secondary variant is outlined (transparent background)" {
  let html = @server_dom.render(button_atom("キャンセル", variant=Secondary))
  assert_true(html.contains("background:transparent"))
  assert_true(html.contains("border:1px solid"))
}

///|
test "button_atom Danger variant uses the danger colour" {
  let html = @server_dom.render(button_atom("削除", variant=Danger))
  assert_true(html.contains("#F87171"))
}

///|
test "enabled button_atom sets cursor:pointer" {
  let html = @server_dom.render(button_atom("実行"))
  assert_true(html.contains("cursor:pointer"))
}

///|
test "disabled button_atom is disabled and not clickable" {
  let html = @server_dom.render(button_atom("実行", disabled=true))
  assert_true(html.contains("disabled"))
  assert_true(html.contains("cursor:not-allowed"))
}

///|
test "button_atom always declares a transition (no instant state change)" {
  let html = @server_dom.render(button_atom("実行"))
  assert_true(html.contains("transition"))
}

///|
test "loading button_atom marks aria-busy and shows a spinner" {
  let html = @server_dom.render(button_atom("送信", loading=true))
  assert_true(html.contains("aria-busy=\"true\""))
  assert_true(html.contains("role=\"status\""))
}

///|
test "button_atom button_type can be submit" {
  let html = @server_dom.render(button_atom("ログイン", button_type="submit"))
  assert_true(html.contains("type=\"submit\""))
}

///|
test "full_width button_atom stretches to 100%" {
  let html = @server_dom.render(button_atom("実行", full_width=true))
  assert_true(html.contains("width:100%"))
}

///|
test "button_atom sizes change padding" {
  let small = @server_dom.render(button_atom("S", size=Small))
  let large = @server_dom.render(button_atom("L", size=Large))
  assert_true(small.contains("padding:6px 12px"))
  assert_true(large.contains("padding:14px 28px"))
}
