///| Tests for the toggle (switch) atom.

///|
test "toggle_atom exposes role=switch and aria-checked" {
  let off = @server_dom.render(toggle_atom(on=false))
  assert_true(off.contains("role=\"switch\""))
  assert_true(off.contains("aria-checked=\"false\""))
  let on = @server_dom.render(toggle_atom(on=true))
  assert_true(on.contains("aria-checked=\"true\""))
}

///|
test "on toggle_atom uses the CTA accent track" {
  let html = @server_dom.render(toggle_atom(on=true))
  assert_true(html.contains("--color-cta"))
}

///|
test "enabled toggle_atom is keyboard focusable and clickable" {
  let html = @server_dom.render(toggle_atom())
  assert_true(html.contains("tabindex=\"0\""))
  assert_true(html.contains("cursor:pointer"))
}

///|
test "disabled toggle_atom is removed from tab order and not clickable" {
  let html = @server_dom.render(toggle_atom(disabled=true))
  assert_true(html.contains("tabindex=\"-1\""))
  assert_true(html.contains("cursor:not-allowed"))
}

///|
test "toggle_atom renders its visible label when provided" {
  let html = @server_dom.render(toggle_atom(on=true, label="Kill Switch"))
  assert_true(html.contains("Kill Switch"))
}

///|
test "toggle_atom thumb moves on state change (transform translate)" {
  let on = @server_dom.render(toggle_atom(on=true))
  let off = @server_dom.render(toggle_atom(on=false))
  assert_true(on.contains("translateX(18px)"))
  assert_true(off.contains("translateX(0)"))
}

///|
test "toggle_atom declares a transition" {
  let html = @server_dom.render(toggle_atom())
  assert_true(html.contains("transition"))
}
