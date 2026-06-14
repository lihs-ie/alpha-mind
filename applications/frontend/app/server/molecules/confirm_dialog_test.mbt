///| Tests for the confirm_dialog molecule.

///|
test "confirm_dialog renders an accessible modal dialog" {
  let html = @server_dom.render(
    confirm_dialog(
      "kill-switch", "kill switch を有効化", "全注文を停止します。",
    ),
  )
  assert_true(html.contains("role=\"dialog\""))
  assert_true(html.contains("aria-modal=\"true\""))
  assert_true(html.contains("kill switch を有効化"))
  assert_true(html.contains("全注文を停止します。"))
}

///|
test "confirm_dialog associates the title and description for screen readers" {
  let html = @server_dom.render(
    confirm_dialog("d1", "確認", "よろしいですか"),
  )
  assert_true(html.contains("aria-labelledby=\"d1-title\""))
  assert_true(html.contains("aria-describedby=\"d1-desc\""))
  assert_true(html.contains("id=\"d1-title\""))
  assert_true(html.contains("id=\"d1-desc\""))
}

///|
test "confirm_dialog is hidden by default and visible when open" {
  let closed = @server_dom.render(confirm_dialog("d2", "t", "m"))
  let open = @server_dom.render(confirm_dialog("d3", "t", "m", open=true))
  assert_true(closed.contains("data-dialog-open=\"false\""))
  assert_true(closed.contains("display:none"))
  assert_true(open.contains("data-dialog-open=\"true\""))
  assert_true(open.contains("display:flex"))
}

///|
test "confirm_dialog renders confirm and cancel buttons with custom labels" {
  let html = @server_dom.render(
    confirm_dialog(
      "d4",
      "却下",
      "この注文を却下しますか",
      confirm_label="却下する",
      cancel_label="やめる",
    ),
  )
  assert_true(html.contains("却下する"))
  assert_true(html.contains("やめる"))
}

///|
test "destructive confirm_dialog uses the danger-coloured confirm button" {
  let html = @server_dom.render(
    confirm_dialog("d5", "削除", "削除しますか", kind=Destructive),
  )
  // Danger button atom uses #F87171
  assert_true(html.contains("#F87171"))
}

///|
test "default confirm_dialog uses the CTA-coloured confirm button" {
  let html = @server_dom.render(
    confirm_dialog("d6", "承認", "承認しますか", kind=Default),
  )
  assert_true(html.contains("--color-cta"))
}
