///| Tests for the typography atoms.

///|
test "heading_atom H1 renders an <h1>" {
  let html = @server_dom.render(heading_atom("ダッシュボード", level=H1))
  assert_true(html.contains("<h1"))
  assert_true(html.contains("ダッシュボード"))
  assert_true(html.contains("font-weight:700"))
}

///|
test "heading_atom H2 renders an <h2> with uppercase tracking" {
  let html = @server_dom.render(heading_atom("運用状態", level=H2))
  assert_true(html.contains("<h2"))
  assert_true(html.contains("text-transform:uppercase"))
}

///|
test "heading_atom H3 renders an <h3>" {
  let html = @server_dom.render(heading_atom("詳細", level=H3))
  assert_true(html.contains("<h3"))
}

///|
test "body_text_atom renders a <p>" {
  let html = @server_dom.render(body_text_atom("本文テキスト"))
  assert_true(html.contains("<p"))
  assert_true(html.contains("本文テキスト"))
}

///|
test "muted body_text_atom uses the muted colour" {
  let html = @server_dom.render(body_text_atom("補足", muted=true))
  assert_true(html.contains("rgba(248,250,252,0.6)"))
}

///|
test "mono_text_atom uses the JetBrains Mono face" {
  let html = @server_dom.render(mono_text_atom("+1,234.56"))
  assert_true(html.contains("JetBrains Mono"))
  assert_true(html.contains("+1,234.56"))
}
