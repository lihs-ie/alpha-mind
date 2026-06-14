///| Tests for the card and stat_card molecules.

///|
test "card renders body content on a design-system surface" {
  let html = @server_dom.render(card([@server_dom.text("本文")]))
  assert_true(html.contains("本文"))
  assert_true(html.contains("--color-surface"))
}

///|
test "card uses the design-system radius and shadow tokens" {
  let html = @server_dom.render(card([@server_dom.text("x")]))
  assert_true(html.contains("--radius-md"))
  assert_true(html.contains("--shadow-md"))
}

///|
test "card with a title renders an h3 heading" {
  let html = @server_dom.render(
    card([@server_dom.text("body")], title="ポートフォリオ"),
  )
  assert_true(html.contains("<h3"))
  assert_true(html.contains("ポートフォリオ"))
}

///|
test "card without a title omits the heading" {
  let html = @server_dom.render(card([@server_dom.text("body")]))
  assert_false(html.contains("<h3"))
}

///|
test "card renders header actions and a footer" {
  let html = @server_dom.render(
    card(
      [@server_dom.text("body")],
      title="設定",
      actions=[@atoms.button_atom("編集", size=Small)],
      footer=[@server_dom.text("更新: 2026-06-15")],
    ),
  )
  assert_true(html.contains("編集"))
  assert_true(html.contains("更新: 2026-06-15"))
}

///|
test "card always declares a transition (no instant state change)" {
  let html = @server_dom.render(card([@server_dom.text("x")]))
  assert_true(html.contains("transition"))
}

///|
test "stat_card renders the label and a monospace value" {
  let html = @server_dom.render(stat_card("評価額", "1,234,567"))
  assert_true(html.contains("評価額"))
  assert_true(html.contains("1,234,567"))
  assert_true(html.contains("JetBrains Mono"))
}

///|
test "stat_card profit delta uses the CTA accent colour" {
  let html = @server_dom.render(
    stat_card("損益", "+12,000", delta="+1.2%", delta_kind=Profit),
  )
  assert_true(html.contains("+1.2%"))
  assert_true(html.contains("--color-cta"))
}

///|
test "stat_card loss delta uses the loss colour" {
  let html = @server_dom.render(
    stat_card("損益", "-8,000", delta="-0.8%", delta_kind=Loss),
  )
  assert_true(html.contains("-0.8%"))
  assert_true(html.contains("#F87171"))
}

///|
test "stat_card without a delta omits the delta node" {
  let html = @server_dom.render(stat_card("件数", "42"))
  assert_true(html.contains("42"))
  assert_true(html.contains("display:none"))
}
