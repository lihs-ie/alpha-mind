///| Tests for the icon atom.

///|
test "icon_atom renders an <svg> with a <path> (no emoji)" {
  let html = @server_dom.render(icon_atom(Check))
  assert_true(html.contains("<svg"))
  assert_true(html.contains("<path"))
  assert_true(html.contains("viewBox=\"0 0 24 24\""))
}

///|
test "decorative icon_atom (no label) is aria-hidden" {
  let html = @server_dom.render(icon_atom(Close))
  assert_true(html.contains("aria-hidden=\"true\""))
}

///|
test "labelled icon_atom exposes role=img and aria-label" {
  let html = @server_dom.render(icon_atom(Warning, label="警告"))
  assert_true(html.contains("role=\"img\""))
  assert_true(html.contains("aria-label=\"警告\""))
}

///|
test "icon_atom size is configurable" {
  let html = @server_dom.render(icon_atom(ArrowRight, size="32"))
  assert_true(html.contains("width=\"32\""))
  assert_true(html.contains("height=\"32\""))
}

///|
test "each named icon produces a distinct path" {
  let check = @server_dom.render(icon_atom(Check))
  let close = @server_dom.render(icon_atom(Close))
  assert_not_eq(check, close)
}
