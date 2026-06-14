///| Tests for the spinner atom.

///|
test "spinner_atom renders an <svg> with role=status" {
  let html = @server_dom.render(spinner_atom())
  assert_true(html.contains("<svg"))
  assert_true(html.contains("role=\"status\""))
}

///|
test "spinner_atom exposes an accessible aria-label" {
  let html = @server_dom.render(spinner_atom(label="送信中"))
  assert_true(html.contains("aria-label=\"送信中\""))
}

///|
test "spinner_atom animates (no instant/static-only state)" {
  let html = @server_dom.render(spinner_atom())
  assert_true(html.contains("animation:alpha-spin"))
}

///|
test "spinner_atom size changes dimensions" {
  let small = @server_dom.render(spinner_atom(size=Small))
  let large = @server_dom.render(spinner_atom(size=Large))
  assert_true(small.contains("width=\"16\""))
  assert_true(large.contains("width=\"40\""))
}
